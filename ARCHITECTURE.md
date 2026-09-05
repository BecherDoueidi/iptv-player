# Architecture

## Layers

```
App/                  Thin app-shell: entry point, DI container, root routing
Features/             SwiftUI views + view models, colocated by feature (no
                       separate UseCase/Interactor ceremony — a view model
                       talking directly to MediaProvider and ModelContext is
                       fine at this scale)
Packages/IPTVCore/    Local Swift package — Domain, XtreamProvider (Data),
                       Persistence, DownloadEngine, Keychain. Testable via
                       `swift test`, no simulator needed.
```

`Packages/IPTVCore` is the one architectural boundary worth enforcing: everything
Xtream-specific (URL conventions, quirky JSON, lenient decoding) is quarantined in
`XtreamProvider/`. The rest of the app talks only to the provider-agnostic
`MediaProvider` protocol and `Domain/` value types.

## Identity: `contentKey`

Every piece of provider content is addressed by `sourceID|kind|providerID`
(`ContentKey.make`), where `sourceID` is a stable hash of the server URL + username.
This is what lets favorites/ratings/downloads/watch-progress survive a full
catalog resync (they're keyed by `contentKey`, not by a SwiftData relationship to
the disposable `Movie`/`TVSeries` mirror rows), and prevents two different
Xtream accounts from ever colliding on the same numeric provider ID.

## Persistence

SwiftData, one `ModelContainer` covering: `ProviderAccount`, `Movie`,
`TVSeries`/`TVSeason`/`TVEpisode` (the one real `@Relationship` tree — genuinely
hierarchical, always loaded together), `WatchProgress`, `Download`, `Favorite`,
`Rating`, `MediaCollection`. All soft-keyed by `contentKey` except the
Series→Season→Episode tree.

Several model names are deliberately compound (`MediaCategory`, `MediaCollection`,
`TVSeries`/`TVSeason`/`TVEpisode`) rather than the bare, more obvious names
(`Category`, `Collection`, `Series`/`Season`/`Episode`). This isn't stylistic — a
type named plain `Category` produced a genuine "ambiguous for type lookup" build
failure once the app target's frameworks were linked in (something else in scope
was also named `Category`), and `Collection` would certainly collide with the
Swift standard library's `Collection` protocol. Every model added afterward was
named defensively to avoid the same class of bug.

## Playback: VLCKit, not AVPlayer

The original design chose `AVPlayerViewController` for its free PiP, AirPlay, and
native transport chrome. That turned out to be unshippable: **AVFoundation cannot
open Matroska (`.mkv`), AVI, or raw TS containers**, and most of a real Xtream
catalog is MKV. On-device this surfaced as a bare "Cannot Open" — the stream URL
was correct all along. This is precisely why SmartersPlayer and every other IPTV
client embeds VLC.

So playback runs on `VLCKitSPM` (MobileVLCKit 3.5.x) via `VLCPlaybackController`,
with hand-built transport controls in `PlayerScreen`. Two deliberate
risk-reduction choices, since this project has no local compiler and CI is the
only build:

- **Polling VLC's public properties on a timer** rather than conforming to
  `VLCMediaPlayerDelegate`, whose Swift signatures vary between VLCKit versions.
- **`as X?` casts** when reading `time`/`length`, which compile whether VLCKit's
  ObjC headers expose those as optional, implicitly-unwrapped, or non-optional.

`AVAudioSession` is configured explicitly (`.playback`) — `AVPlayerViewController`
did that implicitly, and without it VLC's audio is silenced by the ring/silent
switch.

**Known regression:** PiP and AirPlay are gone; they came free with AVKit and VLC
3.5 doesn't provide them. Accepted trade-off for playing the formats that actually
exist in the catalog.

CI verifies `MobileVLCKit.framework` is actually embedded in the built `.app` — a
missing embedded framework wouldn't fail the build, it would dyld-crash on launch,
costing a sideload and a scarce free-tier App ID slot to discover.

## Download engine

`DownloadManager` (`@MainActor`) owns one background `URLSession`
(`delegateQueue: .main`, deliberately — lets delegate callbacks touch SwiftData's
`ModelContext` directly without cross-actor `Sendable` machinery, a simplification
appropriate for a personal app's single instance, not a general pattern). Delegate
methods are `nonisolated` + `MainActor.assumeIsolated`, not `Task { @MainActor in
}`, because `didFinishDownloadingTo`'s temp file is deleted the instant that
method returns — it must be moved synchronously.

Relaunch recovery cross-references live OS-tracked tasks against persisted
`Download` rows so the UI never shows a stale "downloading" state, and sweeps
orphaned files with no matching row. A 100KB floor on completed files catches a
common Xtream-panel failure mode: an HTML error page returned with a 200 status
instead of real video.

**Known limitation:** if a background download completes while the app is fully
killed and iOS relaunches it, there's a narrow race where
`handleEventsForBackgroundURLSession` could fire before `AppDependencies` finishes
constructing, in which case its completion handler is never captured. The
download itself still completes correctly via the delegate callbacks either way —
only the OS's bookkeeping of "app finished handling this" is skipped. This is a
real background-execution scenario that can't be verified from CI; flagged for
manual on-device verification rather than silently assumed safe.

## Build/signing pipeline

No local Xcode, ever — see the [README](README.md) for the full zero-Mac CI/CD
explanation. In short: XcodeGen generates the `.xcodeproj` from `project.yml` on
every CI run; GitHub Actions builds an intentionally *unsigned* `.ipa`; Sideloadly
(or AltStore/SideStore) does the actual Apple-ID signing on-device at install
time. `GENERATE_INFOPLIST_FILE: NO` + explicit `INFOPLIST_FILE` in `project.yml`
matter more than they look — Xcode's modern build system silently auto-generates
an Info.plist from build settings otherwise, ignoring a hand-written file
entirely (this is exactly how an ATS exception silently failed to ship across
several early builds before the CI diagnostic step caught it).

## Testing

Pure logic (Xtream decoding quirks, `WatchProgressPolicy`, `ContentKey`,
`XtreamURLBuilder`, the real Keychain round-trip) is covered by `swift test`
against the `IPTVCore` package — no simulator needed, runs in CI on every push.
SwiftUI view/view-model code is verified by CI compiling successfully plus manual
on-device testing; there's no XCTest UI-test target yet (deliberately deferred —
see the plan's testing-strategy rationale for when that trade-off flips).

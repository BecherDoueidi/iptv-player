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

`DownloadManager` (`@MainActor`) owns one `URLSession` (`delegateQueue: .main`,
deliberately — lets delegate callbacks touch SwiftData's `ModelContext` directly
without cross-actor `Sendable` machinery, a simplification appropriate for a
personal app's single instance, not a general pattern). Delegate methods are
`nonisolated` + `MainActor.assumeIsolated`.

The engine is shaped almost entirely by one property of the target panels: **they
close the connection every ~25 MB of a multi-hundred-megabyte file.** Four
consequences, each of which was a shipped bug first:

1. **Not a background session.** `URLSessionConfiguration.background` transfers
   out-of-process via `nsurlsessiond`, which these panels cut off after a few
   kilobytes — while VLC streams the identical URLs fine. A default session behaves
   like a normal client and transfers at full speed. The cost is that downloads only
   run while the app is active; `resumeInterruptedDownloads()` continues them on
   foreground, which is affordable only because of (2).
2. **Not a download task.** `URLSessionDownloadTask` only hands over its data when a
   segment *completes*, so every mid-segment drop discarded the whole segment — the
   download restarted from zero, forever. A `URLSessionDataTask` appends each chunk
   to a `.part` file as it arrives, so the file on disk is always an accurate record
   of what has been received and the next `Range: bytes=<offset>-` is always correct.
3. **A clean close is not a completed download.** `URLSession` reports a truncated
   transfer as a success; truncation is detected by comparing bytes on disk against
   `Content-Length`. A 200 in reply to a `Range` request means the server ignored it,
   where appending would silently corrupt the file — that case fails loudly instead.
4. **Reconnects back off.** Panels cap concurrent connections per account and answer
   a request over the cap with a bare 404, so an instant reconnect (before the lost
   socket is released server-side) trips it. 0.75s after a productive segment; longer
   after one that transferred nothing, where the cap is the likely cause. A refusal
   with bytes already on disk is retried; a refusal on the very first request is not.

Progress mutations are throttled to 1/sec: SwiftData notifies every `@Query`
observing `Download` on each mutation, and re-rendering an episode list on the main
thread starves the very callbacks driving the transfer.

Relaunch reconciliation keeps `.part` files, so an interrupted download resumes
rather than restarting. A 100KB floor on completed files catches a common panel
failure mode: an HTML error page returned with a 200 status instead of real video.

**Practical constraint, not a code issue:** with a 1-connection account, playback and
downloading fight over the same slot and knock each other out.

## Live TV

`get_live_categories`/`get_live_streams` mirrored into `LiveChannel` rows, cached and
persisted with the same bulk-fetch-and-map approach as the movie/series catalogs (a
query per row is what froze those screens; live lists are larger still).

EPG is fetched per channel on demand from `get_short_epg`, never inline in rows —
it's one request per channel against lists of thousands. Titles and descriptions come
back base64-encoded, timestamps as either a unix epoch or a formatted string, and
panels are inconsistent about all of it, so decoding tolerates every combination and
treats a value that isn't valid base64 as already-plain text.

`PlaybackRequest.isLive` suppresses the scrubber, skip buttons, resume position and
watch-progress rows — none of which mean anything for a continuous stream. Channels
are requested as MPEG-TS (`/live/{user}/{pass}/{id}.ts`), which VLC opens faster than
the panel's HLS alternative.

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

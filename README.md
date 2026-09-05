# IPTV Player (personal, private use)

A native SwiftUI iOS app for watching movies/series from a personal, authorized
Xtream-Codes-compatible source. Built and sideloaded entirely for free, without
owning a Mac. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for design details once
later phases add it.

## Status: MVP complete (Phases 0–10)

Xtream login, Movies/Series browsing (with offline fallback to cached data),
playback via AVPlayerViewController (resume, completion tracking, autoplay-next
prompt), a real background-capable download engine with an offline library,
local search, favorites/ratings/collections, and a Settings screen covering
account/playback/downloads/appearance/data management — all built and verified
via CI on every commit. See the git history for the phase-by-phase build order.

Deferred past MVP (per the original plan): the local recommendation engine,
"What Should I Watch?", "Tonight" mode, and intro/credits-skip UI.

## How this gets built without a Mac

1. **Source is edited in any text editor** (no Xcode GUI is ever used or needed).
2. **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** turns the checked-in
   [`project.yml`](project.yml) into a real `.xcodeproj` — regenerated fresh on
   every CI run, never hand-edited or committed (`.xcodeproj/` is gitignored).
3. **GitHub Actions' free macOS runners** (`.github/workflows/`) run `xcodegen
   generate`, `swift test`, and `xcodebuild build`/`archive` — this is the only
   place actual compilation happens.
4. **The `.ipa` produced is intentionally unsigned.** No Apple ID, certificate,
   or provisioning profile ever touches CI. This is the standard distribution
   format for hobbyist iOS apps sideloaded via tools like Sideloadly/AltStore.
5. **[Sideloadly](https://sideloadly.io/)** (free, runs on Windows) signs the
   `.ipa` with your own free Apple ID and installs it over USB. Unlike
   AltStore/AltServer it has no persistent background service — you just run
   it again whenever you need to (re-)install, including the mandatory 7-day
   free-signature refresh.

## Workflows

- **`build.yml`** — runs on every push/PR to `main`: generates the project,
  runs `IPTVCore` package unit tests, and does an unsigned build. Cheap, fast,
  no artifact produced — just a correctness gate.
- **`release.yml`** — manual dispatch (Actions tab → "Release (unsigned IPA)"
  → "Run workflow"), or automatically on pushing a `v*` tag. Produces
  `IPTVPlayer-unsigned.ipa` as a downloadable workflow artifact, and also
  attaches it to a GitHub Release when triggered by a tag.

## Getting the app onto your iPhone

1. Trigger `release.yml` (push a tag like `v0.1.0`, or run it manually from
   the Actions tab).
2. Download `IPTVPlayer-unsigned.ipa` from the workflow run's artifacts (or
   the GitHub Release page).
3. Install **[Sideloadly](https://sideloadly.io/)** on your Windows PC (also
   installs the Apple Mobile Device Support drivers it needs for USB, if you
   don't already have iTunes). It's free — no license, no subscription.
4. Plug your iPhone into the PC via USB (trust the computer on the phone if
   prompted). In Sideloadly, drag in `IPTVPlayer-unsigned.ipa`, enter your
   Apple ID when prompted, and click Start. Your Apple ID is only used
   locally by Sideloadly to request a free signing certificate from Apple —
   it never touches this project's code or CI.
5. The installed app expires after **7 days** (a hard Apple restriction on
   free, non-paid-Program signing — not something Sideloadly or this project
   can avoid). Re-run Sideloadly with the same `.ipa` before then to refresh
   it. There's no automatic background refresh with this tool, unlike
   AltStore/SideStore — it's a manual once-a-week rerun in exchange for a
   simpler, no-background-service setup.

## Local development notes (if you ever get Mac access)

`make generate`, `make build`, and `make test` wrap the same steps CI runs —
see [`Makefile`](Makefile). On Windows, just edit files and push; let CI do
the building.

## Non-goals

No App Store distribution, no backend, no accounts, no analytics, no paid
services of any kind. See the project plan for the full phased roadmap.

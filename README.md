# IPTV Player (personal, private use)

A native SwiftUI iOS app for watching movies/series from a personal, authorized
Xtream-Codes-compatible source. Built and sideloaded entirely for free, without
owning a Mac. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for design details once
later phases add it.

## Status: Phase 0 — pipeline de-risking

This repo currently contains only a trivial "Hello World" screen. Its entire
purpose is to prove the zero-Mac build-and-sideload pipeline works end-to-end
before any real feature is built. Nothing past this point should be trusted
until that's confirmed on a real device.

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
   format for hobbyist iOS apps sideloaded via AltStore/SideStore.
5. **AltStore or SideStore** (free, open-source, running on your Windows PC)
   sign the `.ipa` in place with your own free Apple ID when you install it,
   and handle the mandatory 7-day free-signature refresh automatically.

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
3. Install **[AltServer](https://altstore.io/)** (Windows build available) or
   set up **[SideStore](https://sidestore.io/)** — either works; SideStore
   needs an AltServer-assisted one-time bootstrap, then can refresh more
   independently afterward. Pick one and stick with it.
4. Plug in your iPhone (or connect over the same Wi-Fi, depending on the tool)
   and use "Install IPA" / drag-and-drop the downloaded `.ipa` file. You'll be
   prompted for your Apple ID the first time — this stays local to
   AltServer/SideStore and is never seen by this project's code or CI.
5. The app will expire in 7 days unless AltServer/SideStore refreshes it —
   keep AltServer reachable on your PC periodically (or rely on SideStore's
   background refresh) so this happens automatically.

## Local development notes (if you ever get Mac access)

`make generate`, `make build`, and `make test` wrap the same steps CI runs —
see [`Makefile`](Makefile). On Windows, just edit files and push; let CI do
the building.

## Non-goals

No App Store distribution, no backend, no accounts, no analytics, no paid
services of any kind. See the project plan for the full phased roadmap.

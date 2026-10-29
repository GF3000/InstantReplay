# InstantReplay

*[Leer en español](README.es.md)*

Offline instant replay for team sports. One Android phone on a tripod films continuously and keeps the last minute in a rolling buffer; the coach's phone or tablet watches the live feed and, with one tap, pulls the last 10–60 seconds to review in slow motion, tag and share. No Internet connection needed: everything runs over a local Wi-Fi network (a phone hotspot or a travel router).

> **Status:** design phase. The architecture and requirements are in [docs/SPEC.md](docs/SPEC.md). Phase 0 (native capture spike) is in progress.

## How it works

- **Camera role** (Android): records 1080p H.264 into a ~80 s ring buffer of 1-second fMP4 fragments, streams a low-latency live view over WebRTC and serves clips over HTTP. Clips are built by concatenating fragments, with no re-encoding and no FFmpeg.
- **Viewer role** (Android): live view, a big *Save* button with presets, a review player (0.25×/0.5×/1×, frame stepping), sessions, one-tap tags, export to the gallery and the system share sheet.
- **Web viewer** (any browser, served by the Camera): live view, save, review and download for the current session.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the toolchain, build and test commands and the PR workflow, and [docs/dev-setup.md](docs/dev-setup.md) for the wireless device loop.

## License

[Apache-2.0](LICENSE)

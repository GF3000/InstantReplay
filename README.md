# InstantReplay

[![CI](https://github.com/GF3000/InstantReplay/actions/workflows/ci.yml/badge.svg)](https://github.com/GF3000/InstantReplay/actions/workflows/ci.yml)

*[Leer en español](README.es.md)*

Offline instant replay for team sports. One Android phone on a tripod films continuously and keeps the last minute in a rolling buffer; the coach's phone or tablet watches the live feed and, with one tap, pulls the last 10–60 seconds to review in slow motion, tag and share. No Internet connection needed: everything runs over a local Wi-Fi network (a phone hotspot or a travel router).

> **Status:** MVP ([v0.3.0](https://github.com/GF3000/InstantReplay/releases/latest)): the Camera records, serves a live view and clips, and can record the whole session; the Viewer (Android app or any browser on the same Wi-Fi) watches live, saves, tags and reviews clips, and on Android keeps a clip library. Field testing is next. Design: [docs/SPEC.md](docs/SPEC.md) · UX: [docs/UX.md](docs/UX.md) · Plan: [docs/PLAN-v0.1.md](docs/PLAN-v0.1.md).
>
> **Try it:** install the APK on an Android phone (10+), follow the [setup guide](docs/setup-guide.md) (Spanish: [guía de montaje](docs/guia-de-montaje.md)).

## How it works

- **Camera role** (Android): records 1080p H.264 into a ~80 s ring buffer of 1-second fMP4 fragments, streams a low-latency live view over WebRTC and serves clips over HTTP. Clips are built by concatenating fragments, with no re-encoding and no FFmpeg.
- **Web Viewer** (any browser on the same Wi-Fi, served by the Camera; scan its QR): live view, a big *Save* button (20 s, or 10/30/60), one-tap tags right after saving, a clip list with thumbnails and tag filters, and a review player (loop, 0.25×/0.5×/1×, frame stepping, download). Clips live in the browser tab for the current session.
- **Native Viewer** (Android, planned): the same plus a persistent library, gallery export and the system share sheet.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the toolchain, build and test commands and the PR workflow, and [docs/dev-setup.md](docs/dev-setup.md) for the wireless device loop.

## License

[Apache-2.0](LICENSE)

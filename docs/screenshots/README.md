# Screenshots

Marketing shots of the real app screens, with sample data, inside phone / tablet / laptop frames.
They are generated, not taken by hand: change the UI, run the command again.

```bash
cd app
flutter test marketing
```

Generated here (ES and EN each):

| File | Device | Shows |
|---|---|---|
| `phone-viewer-*.png` | Android phone, portrait | Live view, Save, quick saves, tagged clips |
| `tablet-broadcast-*.png` | Android tablet, landscape | Broadcast mode: live on YouTube, scoreboard, recording |
| `tablet-telestrator-*.png` | Android tablet, landscape | Clip review with an arrow and a circle drawn |
| `laptop-viewer-*.png` | Laptop | The Viewer in a browser |

The PNGs have a transparent background outside the device.

## Real photos instead of the drawn pitch

Without photos the video is a drawn football pitch. To use real footage, put 16:9 JPG or PNG
frames in `app/marketing/frames/`:

- `live.jpg`: the live view
- `review.jpg`: the paused frame of the telestrator shot
- `clip1.jpg` … `clip6.jpg`: clip thumbnails (optional; missing ones reuse `live.jpg`)

The arrow and the circle of the telestrator shot go where `photoMarks` in
`app/marketing/support/harness.dart` says, as fractions of `review.jpg` (0,0 top left, 1,1 bottom
right): move them when you change that photo.

The frames there now come from our own match (handball, 2026), cropped to drop the streaming
app's watermark. To take new ones from a match video:

```bash
ffmpeg -ss 00:19:00 -i match.mp4 -frames:v 1 -vf "crop=1600:900:320:60" -q:v 3 live.jpg
```

Only commit photos you are allowed to publish (your own, with the players' consent).

## How it works

- `app/marketing/screenshots_test.dart` pumps the real `ViewerPage` and `ReviewPage` with the
  providers overridden (connected camera, clips, tags, scoreboard, broadcast), the way the widget
  tests do. The live view and the video player show the photo instead of WebRTC / a decoder.
- `app/marketing/support/harness.dart` loads Roboto and Material Icons (tests render boxes
  otherwise), wraps the screen in a `device_frame` frame with a status bar, and writes the PNG.
- It lives outside `app/test/`, so `flutter test` and CI do not run it.

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'clip_store.dart';

ClipStore createPlatformClipStore({ClipCatalog? catalog}) => _BlobClipStore();

StoredClip openStoredClip(String clipId, String path, int length) =>
    throw UnsupportedError('The web Viewer has no library (D15)');

/// Web: bytes stay in memory as a Blob and play through an object URL. Lost on reload (D15).
class _BlobClipStore implements ClipStore {
  @override
  Future<StoredClip> store(String clipId, Uint8List bytes) async {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'video/mp4'));
    return _BlobClip(clipId, web.URL.createObjectURL(blob), bytes.length);
  }
}

class _BlobClip implements StoredClip {
  _BlobClip(this.clipId, this.url, this.length);

  @override
  final String clipId;
  final String url;
  @override
  final int length;

  @override
  VideoPlayerController createPlayer() => VideoPlayerController.networkUrl(Uri.parse(url));

  @override
  bool get canDownload => true;

  @override
  String? get filePath => null;

  @override
  Future<void> download(String fileName) async {
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
  }

  /// Loads the blob into an offscreen video element, seeks to ~1 s and draws that frame to a canvas.
  @override
  Future<Uint8List?> thumbnail() async {
    const width = 192;
    const timeout = Duration(seconds: 10);
    final video = web.HTMLVideoElement()
      ..muted = true
      ..playsInline = true
      ..preload = 'auto';
    final loaded = _next(web.EventStreamProviders.loadedDataEvent, video, timeout);
    video.src = url;
    try {
      await loaded;
      final d = video.duration;
      final at = d.isFinite && d > 0 ? math.min(1.0, d / 2) : 0.0;
      if (at > 0) {
        final seeked = _next(web.EventStreamProviders.seekedEvent, video, timeout);
        video.currentTime = at;
        await seeked;
      }
      final (w, h) = (video.videoWidth, video.videoHeight);
      if (w == 0 || h == 0) return null;
      final canvas = web.HTMLCanvasElement()
        ..width = width
        ..height = (width * h / w).round();
      (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(video, 0, 0, canvas.width, canvas.height);
      return UriData.parse(canvas.toDataURL('image/jpeg', 0.75.toJS)).contentAsBytes();
    } catch (_) {
      return null;
    } finally {
      video.removeAttribute('src');
      video.load();
    }
  }

  @override
  Future<void> release() async => web.URL.revokeObjectURL(url);

  /// The next [event] on [video], failing on a media error or after [timeout]. Both listeners are
  /// always cancelled, so a failed grab doesn't keep the element alive.
  static Future<void> _next(
    web.EventStreamProvider<web.Event> event,
    web.HTMLVideoElement video,
    Duration timeout,
  ) {
    final done = Completer<void>();
    final subs = [
      event.forTarget(video).listen((_) => done.isCompleted ? null : done.complete()),
      web.EventStreamProviders.errorEvent.forTarget(video).listen(
            (_) => done.isCompleted ? null : done.completeError(StateError('video error')),
          ),
    ];
    return done.future.timeout(timeout).whenComplete(() {
      for (final s in subs) {
        s.cancel();
      }
    });
  }
}

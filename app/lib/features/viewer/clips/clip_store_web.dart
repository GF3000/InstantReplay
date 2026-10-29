import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'clip_store.dart';

ClipStore createPlatformClipStore() => _BlobClipStore();

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
  Future<void> download(String fileName) async {
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
  }

  @override
  Future<void> release() async => web.URL.revokeObjectURL(url);
}

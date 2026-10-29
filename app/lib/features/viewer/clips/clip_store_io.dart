import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'clip_store.dart';

ClipStore createPlatformClipStore() => _TempFileClipStore();

/// Android: one file per clip under the temp directory, for the current session only.
class _TempFileClipStore implements ClipStore {
  Directory? _dir;

  @override
  Future<StoredClip> store(String clipId, Uint8List bytes) async {
    final dir = _dir ??= await Directory('${(await getTemporaryDirectory()).path}/viewer_clips').create(recursive: true);
    final file = File('${dir.path}/$clipId.mp4');
    await file.writeAsBytes(bytes, flush: true);
    return _FileClip(clipId, file, bytes.length);
  }
}

class _FileClip implements StoredClip {
  _FileClip(this.clipId, this.file, this.length);

  @override
  final String clipId;
  final File file;
  @override
  final int length;

  @override
  VideoPlayerController createPlayer() => VideoPlayerController.file(file);

  // TODO(M4.8): export to the gallery and the system share sheet (SPEC §5.4) instead of a download.
  @override
  bool get canDownload => false;

  @override
  Future<void> download(String fileName) async => throw UnsupportedError('Download is web only');

  @override
  Future<void> release() async {
    if (await file.exists()) await file.delete();
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'clip_store.dart';

ClipStore createPlatformClipStore({ClipCatalog? catalog}) =>
    catalog == null ? _TempFileClipStore() : LibraryClipStore(catalog);

/// Android: each clip goes into the library folder the [catalog] picks and stays there.
class LibraryClipStore implements ClipStore {
  LibraryClipStore(this.catalog);

  final ClipCatalog catalog;

  @override
  Future<StoredClip> store(String clipId, Uint8List bytes) async {
    final file = File(await catalog.pathFor(clipId));
    await file.parent.create(recursive: true);
    // Write next to it and rename, so a killed app never leaves half a clip under the real name.
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
    await catalog.added(clipId, file.path, bytes);
    return FileStoredClip(clipId, file, bytes.length);
  }
}

/// Fallback without a library (tests, desktop): one temp file per clip, for this session only.
class _TempFileClipStore implements ClipStore {
  Directory? _dir;

  @override
  Future<StoredClip> store(String clipId, Uint8List bytes) async {
    final dir = _dir ??= await Directory('${(await getTemporaryDirectory()).path}/viewer_clips').create(recursive: true);
    final file = File('${dir.path}/$clipId.mp4');
    await file.writeAsBytes(bytes, flush: true);
    return FileStoredClip(clipId, file, bytes.length, temporary: true);
  }
}

/// A clip file on disk: in the library, or a temp file that [release] deletes.
class FileStoredClip implements StoredClip {
  FileStoredClip(this.clipId, this.file, this.length, {this.temporary = false});

  @override
  final String clipId;
  final File file;
  @override
  final int length;
  final bool temporary;

  @override
  VideoPlayerController createPlayer() => VideoPlayerController.file(file);

  // TODO(M4.8): export to the gallery and the system share sheet (SPEC §5.4) instead of a download.
  @override
  bool get canDownload => false;

  @override
  Future<void> download(String fileName) async => throw UnsupportedError('Download is web only');

  // video_player cannot hand out frames; the list shows a placeholder until the native library.
  @override
  Future<Uint8List?> thumbnail() async => null;

  @override
  Future<void> release() async {
    if (temporary && await file.exists()) await file.delete();
  }
}

/// A library clip opened from its path, for review.
StoredClip openStoredClip(String clipId, String path, int length) => FileStoredClip(clipId, File(path), length);

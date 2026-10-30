import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'clip_store_io.dart' if (dart.library.js_interop) 'clip_store_web.dart' as platform;

/// Where the Viewer keeps the clips it downloads.
///
/// Web keeps the bytes of the current session in memory and plays them through an object URL
/// (D15). Android writes each clip into the library, `<app files>/clips/<sessionId>/<clipId>.mp4`,
/// and records it through a [ClipCatalog] (SPEC §5.3); without one it falls back to a temp file.
abstract class ClipStore {
  /// The platform store: web or Android. Web ignores [catalog].
  factory ClipStore.platform({ClipCatalog? catalog}) => platform.createPlatformClipStore(catalog: catalog);

  /// A clip already in the Android library, by its file (not available on web).
  static StoredClip openFile(String clipId, String path, int length) => platform.openStoredClip(clipId, path, length);

  Future<StoredClip> store(String clipId, Uint8List bytes);
}

/// One clip held by a [ClipStore].
abstract class StoredClip {
  String get clipId;
  int get length;

  /// A new player for this clip; the caller initializes and disposes it.
  VideoPlayerController createPlayer();

  /// Web can save the MP4 through the browser; Android shares or exports it in a later task.
  bool get canDownload;

  /// Saves the file through the browser (web only).
  Future<void> download(String fileName);

  /// A small JPEG of a frame about 1 s in, for the clip list; null where frames cannot be grabbed
  /// (Android until the native library lands).
  Future<Uint8List?> thumbnail();

  /// Frees the object URL or deletes the temp file. Library clips stay on disk.
  Future<void> release();
}

/// The persistent library behind the Android store: decides where a clip goes and records it.
abstract interface class ClipCatalog {
  /// Absolute path for clip [clipId] in the current library session.
  Future<String> pathFor(String clipId);

  /// The file at [path] now holds clip [clipId] ([bytes] are its contents, for the checksum).
  Future<void> added(String clipId, String path, Uint8List bytes);
}

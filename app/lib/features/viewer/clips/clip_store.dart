import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'clip_store_io.dart' if (dart.library.js_interop) 'clip_store_web.dart' as platform;

/// Where the Viewer keeps the clips of the current session (D15).
///
/// Web keeps the bytes in memory and plays them through an object URL; Android writes a temp file.
/// The persistent library (drift) replaces this on Android later.
abstract class ClipStore {
  /// The platform store: web or Android.
  factory ClipStore.platform() => platform.createPlatformClipStore();

  Future<StoredClip> store(String clipId, Uint8List bytes);
}

/// One clip held by a [ClipStore].
abstract class StoredClip {
  String get clipId;
  int get length;

  /// A new player for this clip; the caller initializes and disposes it.
  VideoPlayerController createPlayer();

  /// Web can save the MP4 through the browser; Android exports [filePath] instead (clip_export.dart).
  bool get canDownload;

  /// The clip's file on disk, for the gallery and share sheet (SPEC §5.4); null on web.
  String? get filePath;

  /// Saves the file through the browser (web only).
  Future<void> download(String fileName);

  /// A small JPEG of a frame about 1 s in, for the clip list; null where frames cannot be grabbed
  /// (Android until the native library lands).
  Future<Uint8List?> thumbnail();

  /// Frees the object URL or deletes the temp file.
  Future<void> release();
}

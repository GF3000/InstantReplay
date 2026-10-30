import 'dart:typed_data';

import 'partial_download_io.dart' if (dart.library.js_interop) 'partial_download_web.dart' as platform;

/// The bytes of a clip received so far, kept between attempts so a cut download resumes with
/// `Range: bytes=<length>-` instead of starting over (SPEC §5.2).
///
/// Android writes a `.part` file under the temp directory; web keeps the bytes in memory.
abstract class PartialDownload {
  /// The platform partial for [clipId]: a temp file on Android, memory on web.
  factory PartialDownload.platform(String clipId) => platform.createPlatformPartialDownload(clipId);

  /// Bytes received so far; the offset of the next request.
  int get length;

  Future<void> append(List<int> chunk);

  /// Everything received, for the checksum and the hand-off to the clip store.
  Future<Uint8List> read();

  /// Drops what was received, to download again from zero.
  Future<void> clear();

  /// Frees the memory or deletes the file.
  Future<void> delete();
}

/// Web, and tests: the bytes stay in memory.
class MemoryPartialDownload implements PartialDownload {
  var _bytes = BytesBuilder(copy: false);

  @override
  int get length => _bytes.length;

  @override
  Future<void> append(List<int> chunk) async => _bytes.add(chunk);

  @override
  Future<Uint8List> read() async => _bytes.toBytes();

  @override
  Future<void> clear() async => _bytes = BytesBuilder(copy: false);

  @override
  Future<void> delete() => clear();
}

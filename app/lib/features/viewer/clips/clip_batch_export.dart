import 'clip_batch_export_io.dart' if (dart.library.js_interop) 'clip_batch_export_web.dart' as platform;
import 'clip_export.dart';

/// One clip of a batch export: its file on disk and the name it gets inside a ZIP.
typedef BatchClip = ({String path, String name});

/// Exports several library clips at once (Android only): joined into one video, or as a ZIP.
abstract final class ClipBatchExport {
  /// Joins [clips] in order into one MP4 named [fileName] (native remux, no re-encode) and saves
  /// it to the gallery, or opens the share sheet when [share] is true.
  static Future<ClipExportResult> joined(List<BatchClip> clips, String fileName, {required bool share}) =>
      platform.joined(clips, fileName, share: share);

  /// Packs [clips] uncompressed into a ZIP named [fileName] and opens the share sheet.
  static Future<ClipExportResult> zip(List<BatchClip> clips, String fileName) => platform.zip(clips, fileName);
}

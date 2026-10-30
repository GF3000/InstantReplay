import 'clip_export_io.dart' if (dart.library.js_interop) 'clip_export_web.dart' as platform;
import 'clip_store.dart';

enum ClipExportResult { done, denied, noSpace, failed }

/// Plain export of a stored clip (SPEC §5.4) to the gallery or the system share sheet.
///
/// The fMP4 + `sidx` file plays as is in the gallery and WhatsApp (PLAN-v0.1, 2026-10-29), so there
/// is no remux. Android only (see Capabilities); web keeps [StoredClip.download].
abstract final class ClipExport {
  /// Copies the clip into the gallery's InstantReplay album as [fileName], asking for storage
  /// access first where the Android version needs it.
  static Future<ClipExportResult> saveToGallery(StoredClip clip, String fileName) =>
      platform.saveToGallery(clip, fileName);

  /// Opens the share sheet with the clip named [fileName].
  static Future<ClipExportResult> share(StoredClip clip, String fileName) => platform.share(clip, fileName);
}

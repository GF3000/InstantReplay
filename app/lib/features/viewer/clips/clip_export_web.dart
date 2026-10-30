import 'clip_export.dart';
import 'clip_store.dart';

// Web saves through the browser download instead ([StoredClip.download]).

Future<ClipExportResult> saveToGallery(StoredClip clip, String fileName) =>
    throw UnsupportedError('Gallery export is Android only');

Future<ClipExportResult> share(StoredClip clip, String fileName) =>
    throw UnsupportedError('Share is Android only');

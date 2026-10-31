import 'clip_batch_export.dart';
import 'clip_export.dart';

Future<ClipExportResult> joined(List<BatchClip> clips, String fileName, {required bool share}) =>
    throw UnsupportedError('Batch export is Android only');

Future<ClipExportResult> zip(List<BatchClip> clips, String fileName) =>
    throw UnsupportedError('Batch export is Android only');

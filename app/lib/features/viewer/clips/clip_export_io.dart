import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'clip_export.dart';
import 'clip_store.dart';

const _album = 'InstantReplay';

Future<ClipExportResult> saveToGallery(StoredClip clip, String fileName) async {
  try {
    // Only Android 10 needs a runtime permission to write to an album; 11+ returns true at once.
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      return ClipExportResult.denied;
    }
    // The gallery takes its display name from the file, so put a copy under [fileName] first.
    final dir = await Directory('${(await getTemporaryDirectory()).path}/clip_export').create(recursive: true);
    final copy = await File(_path(clip)).copy('${dir.path}/$fileName');
    try {
      await Gal.putVideo(copy.path, album: _album);
    } finally {
      await copy.delete();
    }
    return ClipExportResult.done;
  } on GalException catch (e) {
    return switch (e.type) {
      GalExceptionType.accessDenied => ClipExportResult.denied,
      GalExceptionType.notEnoughSpace => ClipExportResult.noSpace,
      _ => ClipExportResult.failed,
    };
  } catch (_) {
    return ClipExportResult.failed;
  }
}

Future<ClipExportResult> share(StoredClip clip, String fileName) async {
  try {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(_path(clip), mimeType: 'video/mp4')],
      fileNameOverrides: [fileName],
    ));
    return ClipExportResult.done;
  } catch (_) {
    return ClipExportResult.failed;
  }
}

String _path(StoredClip clip) => clip.filePath ?? (throw StateError('Clip ${clip.clipId} has no file'));

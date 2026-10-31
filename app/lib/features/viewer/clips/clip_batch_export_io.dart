import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'clip_batch_export.dart';
import 'clip_export.dart';

const _channel = MethodChannel('instant_replay/export');
const _album = 'InstantReplay';

Future<Directory> _workDir() async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/batch_export');
  // Leftovers of an earlier export (the share sheet gives no "done" signal to clean up after).
  if (await dir.exists()) await dir.delete(recursive: true);
  return dir.create(recursive: true);
}

Future<ClipExportResult> joined(List<BatchClip> clips, String fileName, {required bool share}) async {
  try {
    final dir = await _workDir();
    final out = '${dir.path}/$fileName';
    await _channel.invokeMethod<void>('concat', {
      'inputs': [for (final c in clips) c.path],
      'output': out,
    });
    if (share) {
      await SharePlus.instance.share(ShareParams(files: [XFile(out, mimeType: 'video/mp4')]));
      return ClipExportResult.done;
    }
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      return ClipExportResult.denied;
    }
    await Gal.putVideo(out, album: _album);
    await File(out).delete();
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

Future<ClipExportResult> zip(List<BatchClip> clips, String fileName) async {
  try {
    final dir = await _workDir();
    final out = '${dir.path}/$fileName';
    final encoder = ZipFileEncoder()..create(out, level: ZipFileEncoder.store);
    final used = <String>{};
    for (final c in clips) {
      await encoder.addFile(File(c.path), _unique(c.name, used), ZipFileEncoder.store);
    }
    await encoder.close();
    await SharePlus.instance.share(ShareParams(files: [XFile(out, mimeType: 'application/zip')]));
    return ClipExportResult.done;
  } catch (_) {
    return ClipExportResult.failed;
  }
}

/// `name.mp4`, then `name (2).mp4`, … so clips with the same title do not overwrite each other.
String _unique(String name, Set<String> used) {
  final dot = name.lastIndexOf('.');
  final (base, ext) = dot > 0 ? (name.substring(0, dot), name.substring(dot)) : (name, '');
  var candidate = name;
  for (var i = 2; !used.add(candidate); i++) {
    candidate = '$base ($i)$ext';
  }
  return candidate;
}

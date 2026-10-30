import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage_usage.dart';

/// Android: the library directory (`<app files>/clips`, SPEC §5.3) plus this session's clips under
/// the temp directory, where the Viewer keeps them until the library lands.
Future<StorageUsage?> savedClipsUsage() async {
  final dirs = [
    Directory('${(await getApplicationSupportDirectory()).path}/clips'),
    Directory('${(await getTemporaryDirectory()).path}/viewer_clips'),
  ];
  var bytes = 0;
  var clips = 0;
  for (final dir in dirs) {
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.mp4')) continue;
      try {
        bytes += await entity.length();
        clips++;
      } on FileSystemException {
        // Deleted while listing.
      }
    }
  }
  return StorageUsage(bytes: bytes, clips: clips);
}

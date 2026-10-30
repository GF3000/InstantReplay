import 'dart:io';

Future<void> deleteClipFiles(Iterable<String> paths) async {
  for (final p in paths) {
    try {
      final file = File(p);
      if (await file.exists()) await file.delete();
      // Drop the session folder once its last clip is gone.
      final dir = file.parent;
      if (await dir.exists() && await dir.list().isEmpty) await dir.delete();
    } on FileSystemException {
      // Best effort: the row is already gone.
    }
  }
}

import 'library_files_io.dart' if (dart.library.js_interop) 'library_files_web.dart' as platform;

/// Removes clip files the library no longer lists. Missing files are fine.
Future<void> deleteClipFiles(Iterable<String> paths) => platform.deleteClipFiles(paths);

import 'package:drift/drift.dart';

import 'library_connection_io.dart' if (dart.library.js_interop) 'library_connection_web.dart' as platform;

/// The library database file, `<app files>/library.sqlite` (Android). Web has no library (D15).
QueryExecutor openLibraryConnection() => platform.openLibraryConnection();

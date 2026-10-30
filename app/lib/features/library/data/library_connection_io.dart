import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

QueryExecutor openLibraryConnection() =>
    driftDatabase(name: 'library', native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory));

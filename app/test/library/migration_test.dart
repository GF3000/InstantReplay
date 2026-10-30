import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/library/data/library_database.dart';

import 'generated/schema.dart';

/// Schema migrations of the library (SPEC §5.3).
///
/// After changing the tables: bump `schemaVersion`, add the step to `migration.onUpgrade`, then
/// run from `app/`:
///   dart run drift_dev schema dump lib/features/library/data/library_database.dart drift_schemas/library/
///   dart run drift_dev schema generate drift_schemas/library test/library/generated/
/// and add a test below that fills version N with data and checks it after the upgrade.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema version has a saved schema', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(GeneratedHelper.versions.last, db.schemaVersion);
  });

  test('a fresh install creates exactly the current schema', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.validateDatabaseSchema();
  });

  test('every saved version upgrades to the current schema', () async {
    for (final from in GeneratedHelper.versions) {
      final db = LibraryDatabase((await verifier.schemaAt(from)).newConnection());
      await verifier.migrateAndValidate(db, db.schemaVersion);
      await db.close();
    }
  });

  test('foreign keys are enforced after opening', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.single, 1);
  });
}

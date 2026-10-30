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

  test('v1 → v2: categories become tags of their template and clips keep their label', () async {
    final schema = await verifier.schemaAt(1);
    final raw = schema.rawDatabase;
    const t = 1761825600; // 2025-10-30, seconds
    raw.execute(
      "INSERT INTO tag_templates (id, name, sport, built_in, schema_version) VALUES "
      "('builtin.football', NULL, 'football', 1, 1), ('mine', 'Mine', 'rugby', 0, 1)",
    );
    raw.execute(
      'INSERT INTO categories (id, template_id, name, color, position) VALUES '
      "('football.cat.attack', 'builtin.football', NULL, 1, 0), "
      "('football.cat.defense', 'builtin.football', NULL, 2, 1), "
      "('m.cat.press', 'mine', 'Press', 3, 0), "
      "('m.cat.attack', 'mine', 'Attack', 4, 1)",
    );
    raw.execute(
      'INSERT INTO tags (id, template_id, name, color, position) VALUES '
      "('football.tag.goal', 'builtin.football', NULL, 5, 0), "
      "('football.tag.shot', 'builtin.football', 'Tiro', 6, 1), "
      "('m.tag.try', 'mine', 'Try', 7, 0), "
      "('m.tag.attack', 'mine', 'attack', 8, 1)",
    );
    raw.execute(
      "INSERT INTO sessions (id, name, type, started_at, template_id) VALUES "
      "('s1', 'Final', 'match', $t, 'builtin.football'), ('s2', 'Training', 'training', $t, 'mine')",
    );
    for (final (id, session, category) in [
      ('c-cat', 's1', 'football.cat.attack'), // category only → it becomes the tag
      ('c-both', 's1', 'football.cat.defense'), // category and tag → keeps the tag
      ('c-none', 's1', null), // nothing
      ('c-press', 's2', 'm.cat.press'), // a user category
      ('c-same', 's2', 'm.cat.attack'), // a user category named like a tag of the template
    ]) {
      raw.execute(
        'INSERT INTO clips (id, session_id, request_id, requested_at, file_path, size_bytes, category_id, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, 10, ?, ?, ?)',
        [id, session, 'req-$id', t, '/f/$id.mp4', category, t, t],
      );
    }
    raw.execute("INSERT INTO clip_tags (clip_id, tag_id) VALUES ('c-both', 'football.tag.shot')");

    final db = LibraryDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);

    // Built-in template: the categories first, then the tags, ids, names and colours kept.
    final football = (await db.templateContent('builtin.football'))!;
    expect([for (final t in football.tags) (t.id, t.name, t.color, t.position)], [
      ('football.cat.attack', null, 1, 0),
      ('football.cat.defense', null, 2, 1),
      ('football.tag.goal', null, 5, 2),
      ('football.tag.shot', 'Tiro', 6, 3),
    ]);
    // User template: its categories after its tags; one named like a tag is not repeated.
    final mine = (await db.templateContent('mine'))!;
    expect([for (final t in mine.tags) (t.id, t.name)], [
      ('m.tag.try', 'Try'),
      ('m.tag.attack', 'attack'),
      ('m.cat.press', 'Press'),
    ]);

    Future<List<String>> tagsOf(String session, String clip) async =>
        (await db.watchSessionClips(session).first).firstWhere((e) => e.clip.id == clip).tagIds;
    expect(await tagsOf('s1', 'c-cat'), ['football.cat.attack']);
    expect(await tagsOf('s1', 'c-both'), ['football.tag.shot']);
    expect(await tagsOf('s1', 'c-none'), isEmpty);
    expect(await tagsOf('s2', 'c-press'), ['m.cat.press']);
    expect(await tagsOf('s2', 'c-same'), ['m.tag.attack']);

    // Every clip and its other fields survive the rebuilt table; the old table and column are gone.
    final clip = (await db.clip('c-both'))!;
    expect((clip.sessionId, clip.requestId, clip.filePath, clip.sizeBytes), ('s1', 'req-c-both', '/f/c-both.mp4', 10));
    expect(await db.usage(), (50, 5));
    final tables = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    expect([for (final r in tables) r.read<String>('name')], isNot(contains('categories')));
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.data.values.single, 1);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test('foreign keys are enforced after opening', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.single, 1);
  });
}

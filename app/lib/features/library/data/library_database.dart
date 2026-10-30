import 'dart:convert';
import 'dart:developer';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'templates.dart';

part 'library_database.g.dart';

// region Tables (SPEC §5.3)

enum SessionType { match, training, other }

@DataClassName('TemplateRow')
class TagTemplates extends Table {
  TextColumn get id => text()();

  /// Null for a built-in template (localized by id).
  TextColumn get name => text().nullable()();
  TextColumn get sport => text()();
  BoolColumn get builtIn => boolean().withDefault(const Constant(false))();
  IntColumn get schemaVersion => integer().withDefault(const Constant(TemplateSpec.schemaVersion))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<SessionType>()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get templateId => text().nullable().references(TagTemplates, #id, onDelete: KeyAction.setNull)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(TagTemplates, #id, onDelete: KeyAction.cascade)();

  /// Null for a built-in tag (localized by id).
  TextColumn get name => text().nullable()();
  IntColumn get color => integer()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ClipRow')
class Clips extends Table {
  /// The Camera's clip id.
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// The Viewer's save request; the live screen tags a clip by it before the clip id is known.
  TextColumn get requestId => text().nullable()();
  TextColumn get cameraId => text().nullable()();
  DateTimeColumn get requestedAt => dateTime()();

  /// Camera wall-clock time of the save.
  DateTimeColumn get cameraTime => dateTime().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get filePath => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// v0.2, non-destructive trim.
  IntColumn get trimStartMs => integer().nullable()();
  IntColumn get trimEndMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// No foreign key on [tagId]: deleting a tag (and undoing it) keeps the clips' links, like the
/// session tag set did. Links to a tag that no longer exists are ignored.
@DataClassName('ClipTagRow')
class ClipTags extends Table {
  TextColumn get clipId => text().references(Clips, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text()();

  @override
  Set<Column<Object>> get primaryKey => {clipId, tagId};
}

// endregion

/// A template with its tags in order.
@immutable
class TemplateContent {
  const TemplateContent({required this.template, required this.tags});

  final TemplateRow template;
  final List<TagRow> tags;
}

/// A library row: a session and how many clips it holds.
@immutable
class SessionSummary {
  const SessionSummary({required this.session, required this.clipCount});

  final SessionRow session;
  final int clipCount;
}

/// A clip with the ids of its tags (one at most: the live screen and the review set one).
@immutable
class ClipEntry {
  const ClipEntry({required this.clip, required this.tagIds});

  final ClipRow clip;
  final List<String> tagIds;
}

/// The Viewer's clip library (SPEC §5.3), Android only. Clip files live next to it; this only
/// records their paths.
@DriftDatabase(tables: [TagTemplates, Sessions, Tags, Clips, ClipTags])
class LibraryDatabase extends _$LibraryDatabase {
  /// [legacyTagsJson] is the tag set the Viewer kept in shared_preferences (`viewer.tags`); on
  /// first creation it becomes a template of its own, with the same tag ids.
  LibraryDatabase(super.e, {this.legacyTagsJson, String Function()? newId}) : _newId = newId ?? const Uuid().v4;

  final String? legacyTagsJson;
  final String Function() _newId;

  /// 1: first library. 2: categories merged into tags (one label per clip).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final t in BuiltInTemplates.all) {
            await _insertTemplate(t, builtIn: true);
          }
          await _migrateLegacyTags();
        },
        // Each version adds its step here (see test/library/migration_test.dart).
        onUpgrade: (m, from, to) async {
          // Off while tables are rebuilt, so dropping the old clips table does not cascade.
          await customStatement('PRAGMA foreign_keys = OFF');
          if (from < 2) await _mergeCategoriesIntoTags(m);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // region Templates

  Future<List<TemplateRow>> templates() =>
      (select(tagTemplates)..orderBy([(t) => OrderingTerm.desc(t.builtIn), (t) => OrderingTerm.asc(t.id)])).get();

  Stream<List<TemplateRow>> watchTemplates() =>
      (select(tagTemplates)..orderBy([(t) => OrderingTerm.desc(t.builtIn), (t) => OrderingTerm.asc(t.id)])).watch();

  Future<TemplateContent?> templateContent(String id) async {
    final template = await (select(tagTemplates)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (template == null) return null;
    final tgs = await (select(tags)
          ..where((t) => t.templateId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return TemplateContent(template: template, tags: tgs);
  }

  /// Every tag, for showing clips of any session.
  Future<List<TagRow>> allTags() => select(tags).get();

  /// Adds an imported template (new ids) and returns its id.
  Future<String> importTemplate(TemplateSpec spec) => transaction(() async {
        final id = _newId();
        await _insertTemplate(
          TemplateSpec(
            id: id,
            name: spec.name,
            sport: spec.sport,
            tags: [for (final t in spec.tags) LabelSpec(id: _newId(), name: t.name, color: t.color)],
          ),
          builtIn: false,
        );
        return id;
      });

  /// The template as stored; built-in names stay null (the caller localizes them for export).
  Future<TemplateSpec?> exportTemplate(String id) async {
    final c = await templateContent(id);
    if (c == null) return null;
    return TemplateSpec(
      id: c.template.id,
      name: c.template.name,
      sport: c.template.sport,
      tags: [for (final r in c.tags) LabelSpec(id: r.id, name: r.name, color: r.color)],
    );
  }

  /// Sessions keep their clips; they just lose the template.
  Future<void> deleteTemplate(String id) => (delete(tagTemplates)..where((t) => t.id.equals(id))).go();

  /// Makes [labels] the tags of [templateId], in that order. Missing ones are deleted (their clip
  /// links stay, see [ClipTags]).
  Future<void> replaceTags(String templateId, List<LabelSpec> labels) => transaction(() async {
        await (delete(tags)..where((t) => t.templateId.equals(templateId) & t.id.isNotIn(_ids(labels)))).go();
        for (final (i, l) in labels.indexed) {
          await into(tags).insertOnConflictUpdate(
            TagRow(id: l.id!, templateId: templateId, name: l.name, color: l.color, position: i),
          );
        }
      });

  static List<String> _ids(List<LabelSpec> labels) => [for (final l in labels) l.id!];

  Future<void> _insertTemplate(TemplateSpec t, {required bool builtIn}) async {
    await into(tagTemplates).insert(TagTemplatesCompanion.insert(
      id: t.id!,
      name: Value(t.name),
      sport: t.sport,
      builtIn: Value(builtIn),
    ));
    await batch((b) {
      b.insertAll(tags, [
        for (final (i, g) in t.tags.indexed)
          TagsCompanion.insert(id: g.id!, templateId: t.id!, name: Value(g.name), color: g.color, position: i),
      ]);
    });
  }

  /// v1 → v2: one label per clip. Every template's categories become tags of it, with the same
  /// id, name and colour (built-in templates: before their tags, as [BuiltInTemplates] lists them
  /// now; user templates: after). A category whose name a tag of the template already has is not
  /// copied; its clips get that tag instead. A clip with a category and no tag gets the category
  /// as its tag (a clip with both keeps its tag). Then the categories table and the clips'
  /// category column go.
  Future<void> _mergeCategoriesIntoTags(Migrator m) async {
    final templateRows = await customSelect('SELECT id, built_in FROM tag_templates').get();
    // Category id → the tag id its clips get.
    final tagFor = <String, String>{};
    for (final t in templateRows) {
      final templateId = t.read<String>('id');
      final builtIn = t.read<bool>('built_in');
      final cats = await customSelect(
        'SELECT id, name, color FROM categories WHERE template_id = ? ORDER BY position',
        variables: [Variable(templateId)],
      ).get();
      if (cats.isEmpty) continue;
      final existing = await customSelect(
        'SELECT id, name FROM tags WHERE template_id = ? ORDER BY position',
        variables: [Variable(templateId)],
      ).get();
      String key(String id, String? name) => (name ?? id.split('.').last).trim().toLowerCase();
      final byName = {for (final r in existing) key(r.read<String>('id'), r.read<String?>('name')): r.read<String>('id')};
      final added = <(String, String?, int)>[];
      for (final c in cats) {
        final id = c.read<String>('id');
        final name = c.read<String?>('name');
        final same = byName[key(id, name)];
        if (same != null) {
          tagFor[id] = same;
        } else {
          tagFor[id] = id;
          byName[key(id, name)] = id;
          added.add((id, name, c.read<int>('color')));
        }
      }
      final order = builtIn
          ? [for (final a in added) a.$1, for (final r in existing) r.read<String>('id')]
          : [for (final r in existing) r.read<String>('id'), for (final a in added) a.$1];
      for (final (id, name, color) in added) {
        await customStatement(
          'INSERT OR IGNORE INTO tags (id, template_id, name, color, position) VALUES (?, ?, ?, ?, 0)',
          [id, templateId, name, color],
        );
      }
      for (final (i, id) in order.indexed) {
        await customStatement('UPDATE tags SET position = ? WHERE id = ? AND template_id = ?', [i, id, templateId]);
      }
    }
    final categorized = await customSelect(
      'SELECT id, category_id FROM clips WHERE category_id IS NOT NULL '
      'AND NOT EXISTS (SELECT 1 FROM clip_tags WHERE clip_tags.clip_id = clips.id)',
    ).get();
    for (final c in categorized) {
      final categoryId = c.read<String>('category_id');
      await customStatement(
        'INSERT OR IGNORE INTO clip_tags (clip_id, tag_id) VALUES (?, ?)',
        [c.read<String>('id'), tagFor[categoryId] ?? categoryId],
      );
    }
    // Rebuilds clips without the column (and its reference to categories), keeping every row.
    await m.alterTable(TableMigration(clips));
    await customStatement('DROP TABLE IF EXISTS categories');
  }

  /// `[{"id": "good", "color": 4282622023}, {"id": "…", "name": "Contra", "color": …}]`
  Future<void> _migrateLegacyTags() async {
    final raw = legacyTagsJson;
    if (raw == null) return;
    final List<LabelSpec> labels;
    try {
      labels = [
        for (final j in jsonDecode(raw) as List<dynamic>)
          LabelSpec(
            id: (j as Map<String, dynamic>)['id'] as String,
            name: j['name'] as String?,
            color: j['color'] as int,
          ),
      ];
    } catch (e) {
      log('Legacy tags not migrated: $e', name: 'library');
      return;
    }
    if (labels.isEmpty) return;
    await _insertTemplate(
      TemplateSpec(id: BuiltInTemplates.migrated, sport: 'generic', tags: labels),
      builtIn: false,
    );
  }

  // endregion

  // region Sessions

  Stream<List<SessionSummary>> watchSessions() {
    final count = clips.id.count();
    final query = select(sessions).join([leftOuterJoin(clips, clips.sessionId.equalsExp(sessions.id))])
      ..addColumns([count])
      ..groupBy([sessions.id])
      ..orderBy([OrderingTerm.desc(sessions.startedAt)]);
    return query.watch().map((rows) => [
          for (final r in rows) SessionSummary(session: r.readTable(sessions), clipCount: r.read(count) ?? 0),
        ]);
  }

  Future<SessionRow?> latestSession() =>
      (select(sessions)
            ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<SessionRow?> session(String id) => (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<SessionRow> createSession({
    required String name,
    required SessionType type,
    String? templateId,
    DateTime? startedAt,
  }) async {
    final row = SessionRow(
      id: _newId(),
      name: name,
      type: type,
      startedAt: startedAt ?? DateTime.now(),
      templateId: templateId,
    );
    await into(sessions).insert(row);
    return row;
  }

  /// Deletes the session and its clips; returns the clip files to remove.
  Future<List<String>> deleteSession(String id) => transaction(() async {
        final files = await (selectOnly(clips)
              ..addColumns([clips.filePath])
              ..where(clips.sessionId.equals(id)))
            .map((r) => r.read(clips.filePath)!)
            .get();
        await (delete(sessions)..where((s) => s.id.equals(id))).go();
        return files;
      });

  // endregion

  // region Clips

  Future<void> addClip(ClipsCompanion clip) => into(clips).insertOnConflictUpdate(clip);

  /// Total bytes and number of clips in the library (Settings → storage).
  Future<(int bytes, int clips)> usage() async {
    final (bytes, count) = (clips.sizeBytes.sum(), clips.id.count());
    final row = await (selectOnly(clips)..addColumns([bytes, count])).getSingle();
    return (row.read(bytes) ?? 0, row.read(count) ?? 0);
  }

  Future<ClipRow?> clip(String id) => (select(clips)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Clips of a session with their tag ids, newest first.
  Stream<List<ClipEntry>> watchSessionClips(String sessionId) {
    final query = (select(clips)
          ..where((c) => c.sessionId.equals(sessionId))
          ..orderBy([(c) => OrderingTerm.desc(c.requestedAt)]))
        .join([leftOuterJoin(clipTags, clipTags.clipId.equalsExp(clips.id))]);
    return query.watch().map((rows) {
      final byId = <String, (ClipRow, List<String>)>{};
      for (final r in rows) {
        final c = r.readTable(clips);
        final entry = byId.putIfAbsent(c.id, () => (c, <String>[]));
        if (r.readTableOrNull(clipTags) case final link?) entry.$2.add(link.tagId);
      }
      return [for (final (c, t) in byId.values) ClipEntry(clip: c, tagIds: t)];
    });
  }

  /// Fills in what the Viewer learned about a clip after storing it.
  Future<void> updateClip(String id, ClipsCompanion fields) =>
      (update(clips)..where((c) => c.id.equals(id))).write(fields.copyWith(updatedAt: Value(DateTime.now())));

  /// Replaces the tags of a clip.
  Future<void> setClipTags(String clipId, Iterable<String> tagIds) => transaction(() async {
        await (delete(clipTags)..where((t) => t.clipId.equals(clipId))).go();
        await batch((b) => b.insertAll(clipTags, [
              for (final id in tagIds) ClipTagsCompanion.insert(clipId: clipId, tagId: id),
            ]));
        await updateClip(clipId, const ClipsCompanion());
      });

  /// The clip saved by request [requestId] (or with that clip id, for clips stored without one),
  /// if it is in the library yet.
  Future<String?> clipIdForRequest(String requestId) async {
    final row = await (selectOnly(clips)
          ..addColumns([clips.id])
          ..where(clips.requestId.equals(requestId) | clips.id.equals(requestId))
          ..limit(1))
        .getSingleOrNull();
    return row?.read(clips.id);
  }

  /// Deletes clips; returns their files to remove.
  Future<List<String>> deleteClips(Iterable<String> ids) => transaction(() async {
        final list = ids.toList();
        final files = await (selectOnly(clips)
              ..addColumns([clips.filePath])
              ..where(clips.id.isIn(list)))
            .map((r) => r.read(clips.filePath)!)
            .get();
        await (delete(clips)..where((c) => c.id.isIn(list))).go();
        return files;
      });

  // endregion
}

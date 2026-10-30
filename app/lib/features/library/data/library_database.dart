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

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(TagTemplates, #id, onDelete: KeyAction.cascade)();

  /// Null for a built-in category (localized by id).
  TextColumn get name => text().nullable()();
  IntColumn get color => integer()();
  IntColumn get position => integer()();

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
  TextColumn get categoryId => text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
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

/// A template with its categories and tags in order.
@immutable
class TemplateContent {
  const TemplateContent({required this.template, required this.categories, required this.tags});

  final TemplateRow template;
  final List<CategoryRow> categories;
  final List<TagRow> tags;
}

/// A library row: a session and how many clips it holds.
@immutable
class SessionSummary {
  const SessionSummary({required this.session, required this.clipCount});

  final SessionRow session;
  final int clipCount;
}

/// A clip with the ids of its tags.
@immutable
class ClipEntry {
  const ClipEntry({required this.clip, required this.tagIds});

  final ClipRow clip;
  final List<String> tagIds;
}

/// The Viewer's clip library (SPEC §5.3), Android only. Clip files live next to it; this only
/// records their paths.
@DriftDatabase(tables: [TagTemplates, Sessions, Categories, Tags, Clips, ClipTags])
class LibraryDatabase extends _$LibraryDatabase {
  /// [legacyTagsJson] is the tag set the Viewer kept in shared_preferences (`viewer.tags`); on
  /// first creation it becomes a template of its own, with the same tag ids.
  LibraryDatabase(super.e, {this.legacyTagsJson, String Function()? newId}) : _newId = newId ?? const Uuid().v4;

  final String? legacyTagsJson;
  final String Function() _newId;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final t in BuiltInTemplates.all) {
            await _insertTemplate(t, builtIn: true);
          }
          await _migrateLegacyTags();
        },
        // Later versions add their steps here (see test/library/migration_test.dart).
        onUpgrade: (m, from, to) async {},
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
    final cats = await (select(categories)
          ..where((c) => c.templateId.equals(id))
          ..orderBy([(c) => OrderingTerm.asc(c.position)]))
        .get();
    final tgs = await (select(tags)
          ..where((t) => t.templateId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return TemplateContent(template: template, categories: cats, tags: tgs);
  }

  /// Every tag and category, for showing clips of any session.
  Future<(List<CategoryRow>, List<TagRow>)> allLabels() async => (await select(categories).get(), await select(tags).get());

  /// Adds an imported template (new ids) and returns its id.
  Future<String> importTemplate(TemplateSpec spec) => transaction(() async {
        final id = _newId();
        await _insertTemplate(
          TemplateSpec(
            id: id,
            name: spec.name,
            sport: spec.sport,
            categories: [for (final c in spec.categories) LabelSpec(id: _newId(), name: c.name, color: c.color)],
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
      categories: [for (final r in c.categories) LabelSpec(id: r.id, name: r.name, color: r.color)],
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

  /// Makes [labels] the categories of [templateId], in that order. Clips in a deleted category
  /// become uncategorized.
  Future<void> replaceCategories(String templateId, List<LabelSpec> labels) => transaction(() async {
        await (delete(categories)..where((c) => c.templateId.equals(templateId) & c.id.isNotIn(_ids(labels)))).go();
        for (final (i, l) in labels.indexed) {
          await into(categories).insertOnConflictUpdate(
            CategoryRow(id: l.id!, templateId: templateId, name: l.name, color: l.color, position: i),
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
      b.insertAll(categories, [
        for (final (i, c) in t.categories.indexed)
          CategoriesCompanion.insert(id: c.id!, templateId: t.id!, name: Value(c.name), color: c.color, position: i),
      ]);
      b.insertAll(tags, [
        for (final (i, g) in t.tags.indexed)
          TagsCompanion.insert(id: g.id!, templateId: t.id!, name: Value(g.name), color: g.color, position: i),
      ]);
    });
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

  Future<void> setClipCategory(String clipId, String? categoryId) =>
      updateClip(clipId, ClipsCompanion(categoryId: Value(categoryId)));

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

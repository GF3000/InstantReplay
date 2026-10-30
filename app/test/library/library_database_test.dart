import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/library/data/library_database.dart';
import 'package:instant_replay/features/library/data/templates.dart';

LibraryDatabase _db({String? legacy}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  var n = 0;
  final db = LibraryDatabase(NativeDatabase.memory(), legacyTagsJson: legacy, newId: () => 'id${n++}');
  addTearDown(db.close);
  return db;
}

Future<void> _clip(LibraryDatabase db, String id, String sessionId, {String? requestId, DateTime? at}) => db.addClip(
      ClipsCompanion.insert(
        id: id,
        sessionId: sessionId,
        requestId: Value(requestId),
        requestedAt: at ?? DateTime(2026, 10, 30, 12),
        filePath: '/files/clips/$sessionId/$id.mp4',
        sizeBytes: 100,
        createdAt: DateTime(2026, 10, 30),
        updatedAt: DateTime(2026, 10, 30),
      ),
    );

void main() {
  group('first creation', () {
    test('seeds the five built-in templates with their tags in order', () async {
      final db = _db();
      final templates = await db.templates();
      expect({for (final t in templates) t.id}, {for (final t in BuiltInTemplates.all) t.id});
      expect(templates.every((t) => t.builtIn && t.name == null), isTrue);
      final hockey = (await db.templateContent(BuiltInTemplates.hockey))!;
      final spec = BuiltInTemplates.all.firstWhere((t) => t.id == BuiltInTemplates.hockey);
      expect([for (final t in hockey.tags) t.id], [for (final t in spec.tags) t.id]);
      expect([for (final t in hockey.tags) t.color], [for (final t in spec.tags) t.color]);
    });

    test('moves the shared_preferences tag set into a template of its own, keeping ids', () async {
      final legacy = jsonEncode([
        {'id': 'good', 'color': 0xFF43A047},
        {'id': 'x1', 'name': 'Contra', 'color': 0xFF8E24AA},
      ]);
      final db = _db(legacy: legacy);
      final migrated = (await db.templateContent(BuiltInTemplates.migrated))!;
      expect(migrated.template.builtIn, isFalse);
      expect([for (final t in migrated.tags) (t.id, t.name, t.color)], [
        ('good', null, 0xFF43A047),
        ('x1', 'Contra', 0xFF8E24AA),
      ]);
    });

    test('an unreadable or empty legacy tag set is skipped', () async {
      for (final legacy in ['{oops', '[]', '[{"id": 1}]']) {
        final db = _db(legacy: legacy);
        expect(await db.templateContent(BuiltInTemplates.migrated), isNull, reason: legacy);
        expect(await db.templates(), hasLength(5));
      }
    });
  });

  group('sessions and clips', () {
    test('lists sessions newest first with their clip counts', () async {
      final db = _db();
      final a = await db.createSession(
        name: 'A',
        type: SessionType.training,
        templateId: BuiltInTemplates.generic,
        startedAt: DateTime(2026, 10, 1),
      );
      final b = await db.createSession(name: 'B', type: SessionType.match, startedAt: DateTime(2026, 10, 2));
      await _clip(db, 'c1', a.id);
      await _clip(db, 'c2', a.id);
      final list = await db.watchSessions().first;
      expect([for (final s in list) (s.session.name, s.session.type, s.clipCount)], [
        ('B', SessionType.match, 0),
        ('A', SessionType.training, 2),
      ]);
      expect((await db.latestSession())!.id, b.id);
    });

    test('clips carry their tag, read back newest first', () async {
      final db = _db();
      final s = await db.createSession(name: 'S', type: SessionType.match, templateId: BuiltInTemplates.football);
      await _clip(db, 'old', s.id, requestId: 'r-old', at: DateTime(2026, 10, 30, 12));
      await _clip(db, 'new', s.id, requestId: 'r-new', at: DateTime(2026, 10, 30, 13));
      expect(await db.clipIdForRequest('r-old'), 'old');
      expect(await db.clipIdForRequest('old'), 'old');
      expect(await db.clipIdForRequest('nope'), isNull);

      await db.setClipTags('old', ['football.tag.goal', 'football.tag.shot']);
      final clips = await db.watchSessionClips(s.id).first;
      expect([for (final c in clips) c.clip.id], ['new', 'old']);
      expect(clips.last.tagIds, unorderedEquals(['football.tag.goal', 'football.tag.shot']));
      expect(clips.first.tagIds, isEmpty);

      await db.setClipTags('old', ['football.tag.foul']);
      expect((await db.watchSessionClips(s.id).first).last.tagIds, ['football.tag.foul']);
    });

    test('a deleted tag keeps its clip links, so undo gives it back', () async {
      final db = _db();
      final s = await db.createSession(name: 'S', type: SessionType.match, templateId: BuiltInTemplates.generic);
      await _clip(db, 'c', s.id);
      await db.setClipTags('c', ['generic.tag.good']);
      final content = (await db.templateContent(BuiltInTemplates.generic))!;
      final good = content.tags.firstWhere((t) => t.id == 'generic.tag.good');

      await db.replaceTags(BuiltInTemplates.generic, [
        for (final t in content.tags)
          if (t.id != good.id) LabelSpec(id: t.id, name: t.name, color: t.color),
      ]);
      expect((await db.templateContent(BuiltInTemplates.generic))!.tags, hasLength(content.tags.length - 1));
      expect((await db.watchSessionClips(s.id).first).single.tagIds, ['generic.tag.good']);

      await db.replaceTags(BuiltInTemplates.generic, [
        for (final t in content.tags) LabelSpec(id: t.id, name: t.id == good.id ? 'Great' : t.name, color: t.color),
      ]);
      final again = (await db.templateContent(BuiltInTemplates.generic))!;
      expect([for (final t in again.tags) t.id], [for (final t in content.tags) t.id]);
      expect(again.tags.firstWhere((t) => t.id == good.id).name, 'Great');
    });

    test('batch delete removes clips and their tags and returns the files', () async {
      final db = _db();
      final s = await db.createSession(name: 'S', type: SessionType.other);
      for (final id in ['a', 'b', 'c']) {
        await _clip(db, id, s.id);
      }
      await db.setClipTags('a', ['t']);
      final files = await db.deleteClips(['a', 'b']);
      expect(files, unorderedEquals(['/files/clips/${s.id}/a.mp4', '/files/clips/${s.id}/b.mp4']));
      expect([for (final c in await db.watchSessionClips(s.id).first) c.clip.id], ['c']);
      expect(await db.select(db.clipTags).get(), isEmpty);
    });

    test('deleting a session removes its clips and returns their files', () async {
      final db = _db();
      final s = await db.createSession(name: 'S', type: SessionType.other);
      final keep = await db.createSession(name: 'K', type: SessionType.other);
      await _clip(db, 'a', s.id);
      await _clip(db, 'k', keep.id);
      expect(await db.deleteSession(s.id), ['/files/clips/${s.id}/a.mp4']);
      expect(await db.session(s.id), isNull);
      expect((await db.clip('k'))!.sessionId, keep.id);
      expect(await db.clip('a'), isNull);
    });

    test('deleting a template leaves its sessions without one', () async {
      final db = _db();
      final id = await db.importTemplate(const TemplateSpec(name: 'Mine', sport: 'rugby'));
      final s = await db.createSession(name: 'S', type: SessionType.match, templateId: id);
      await db.deleteTemplate(id);
      expect((await db.session(s.id))!.templateId, isNull);
    });
  });

  group('template import and export', () {
    test('import gives new ids; export returns the same names, colours and order', () async {
      final db = _db();
      const spec = TemplateSpec(
        name: 'Waterpolo',
        sport: 'waterpolo',
        tags: [LabelSpec(name: 'Goal', color: 0xFF00FF00), LabelSpec(name: 'Exclusion', color: 0xFF9E9E9E)],
      );
      final id = await db.importTemplate(spec);
      final out = (await db.exportTemplate(id))!;
      expect(out.name, 'Waterpolo');
      expect(out.sport, 'waterpolo');
      expect([for (final t in out.tags) (t.name, t.color)], [('Goal', 0xFF00FF00), ('Exclusion', 0xFF9E9E9E)]);
      expect(out.tags.every((t) => t.id != null && t.id != id), isTrue);
      // Importing twice gives two templates, not a clash.
      final second = await db.importTemplate(spec);
      expect(second, isNot(id));
      expect(await db.templates(), hasLength(7));
      expect((await db.templateContent(id))!.template.builtIn, isFalse);
    });
  });
}

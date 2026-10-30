import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/library/data/library_database.dart';
import 'package:instant_replay/features/library/data/templates.dart';
import 'package:instant_replay/features/library/library_providers.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Android path: active session → clip store writes into the library → tags follow the
/// session's template and reach the database.
void main() {
  late Directory root;
  late LibraryDatabase db;
  late ProviderContainer c;
  final deleted = <String>[];

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = await Directory.systemTemp.createTemp('library_test');
    db = LibraryDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    deleted.clear();
    c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
      libraryDatabaseProvider.overrideWithValue(db),
      libraryRootProvider.overrideWithValue(() async => root.path),
      clipFileDeleterProvider.overrideWithValue((paths) async => deleted.addAll(paths)),
    ]);
  });

  tearDown(() async {
    c.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  Future<T> eventually<T>(Future<T?> Function() read) async {
    for (var i = 0; i < 100; i++) {
      final v = await read();
      if (v != null) return v;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('timed out');
  }

  test('a stored clip lands in <files>/clips/<session>/<clip>.mp4, is recorded and stays', () async {
    final session = c.read(activeSessionProvider.notifier);
    await session.start(name: 'Final', type: SessionType.match, templateId: BuiltInTemplates.football);
    final id = c.read(activeSessionProvider)!.id;
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));

    final stored = await c.read(clipStoreProvider).store('clip-1', bytes);
    final file = File('${root.path}/clips/$id/clip-1.mp4');
    expect(file.readAsBytesSync(), bytes);
    expect(File('${file.path}.part').existsSync(), isFalse);
    final row = (await db.clip('clip-1'))!;
    expect((row.sessionId, row.filePath, row.sizeBytes), (id, file.path, 1000));
    expect(await eventually(() async => (await db.clip('clip-1'))!.sha256), sha256.convert(bytes).toString());

    // Leaving the live screen releases its clips; library files stay.
    await stored.release();
    expect(file.existsSync(), isTrue);
  });

  test('a clip saved without a session goes into a new Generic one', () async {
    await c.read(clipStoreProvider).store('clip-1', Uint8List(4));
    final s = c.read(activeSessionProvider)!;
    expect(s.templateId, BuiltInTemplates.generic);
    expect((await db.clip('clip-1'))!.sessionId, s.id);
  });

  test("tags follow the session's template; edits are saved to it", () async {
    await c.read(activeSessionProvider.notifier).start(
          name: 'T',
          type: SessionType.training,
          templateId: BuiltInTemplates.basketball,
        );
    final ids = [for (final t in c.read(tagsProvider)) t.id];
    expect(ids.first, 'basketball.cat.attack');
    expect(ids, contains('basketball.tag.basket'));
    expect(ids, hasLength(10));

    c.read(tagsProvider.notifier).add('Block', 0xFF00ACC1);
    c.read(tagsProvider.notifier).remove('basketball.cat.setPiece');
    await eventually(() async {
      final t = (await db.templateContent(BuiltInTemplates.basketball))!;
      return t.tags.length == 10 && t.tags.every((t) => t.id != 'basketball.cat.setPiece') ? t : null;
    });
    final t = (await db.templateContent(BuiltInTemplates.basketball))!;
    expect(t.tags.last.name, 'Block');

    // The shared_preferences set is left alone (web still uses it).
    expect(c.read(sharedPreferencesProvider).getString(TagsNotifier.storageKey), isNull);
  });

  test('tagging a clip in memory reaches the library, before or after it is stored', () async {
    c.listen(clipLabelWriterProvider, (_, _) {});
    await c.read(activeSessionProvider.notifier).start(
          name: 'T',
          type: SessionType.match,
          templateId: BuiltInTemplates.football,
        );
    final sessionId = c.read(activeSessionProvider)!.id;
    await c.read(clipStoreProvider).store('clip-1', Uint8List(4));
    await db.updateClip('clip-1', const ClipsCompanion(requestId: Value('req-1')));

    c.read(clipTagsProvider.notifier).set('req-1', 'football.tag.goal');
    final entry = await eventually(() async {
      final e = (await db.watchSessionClips(sessionId).first).single;
      return e.tagIds.isNotEmpty ? e : null;
    });
    expect(entry.tagIds, ['football.tag.goal']);

    // One tag per clip: a new one replaces it.
    c.read(clipTagsProvider.notifier).set('req-1', 'football.cat.attack');
    await eventually(() async {
      final e = (await db.watchSessionClips(sessionId).first).single;
      return e.tagIds.length == 1 && e.tagIds.single == 'football.cat.attack' ? e : null;
    });

    c.read(clipTagsProvider.notifier).set('req-1', null);
    await eventually(() async => (await db.watchSessionClips(sessionId).first).single.tagIds.isEmpty ? true : null);
  });

  test("library label choices: the session's template, live labels for the active one", () async {
    final old = await db.createSession(name: 'Old', type: SessionType.match, templateId: BuiltInTemplates.hockey);
    final gone = await db.createSession(name: 'Gone', type: SessionType.match, templateId: BuiltInTemplates.handball);
    await db.deleteTemplate(BuiltInTemplates.handball);
    await c.read(activeSessionProvider.notifier).start(
          name: 'Now',
          type: SessionType.match,
          templateId: BuiltInTemplates.football,
        );

    final choices = (await libraryLabelChoices(c.read, old.id))!;
    expect(choices.tags.first.id, 'hockey.cat.attack');
    expect([for (final t in choices.tags) t.id], contains('hockey.tag.goal'));
    expect(await libraryLabelChoices(c.read, c.read(activeSessionProvider)!.id), isNull);
    final none = (await libraryLabelChoices(c.read, gone.id))!;
    expect(none.tags, isEmpty);
  });

  test('the post-save bar: one tap tags the clip and closes it', () async {
    await c.read(activeSessionProvider.notifier).start(
          name: 'T',
          type: SessionType.match,
          templateId: BuiltInTemplates.handball,
        );
    final bar = c.read(postSaveTagBarProvider.notifier);
    bar.show('req-1');
    expect(c.read(postSaveTagBarProvider), 'req-1');
    bar.pick('handball.tag.save');
    expect(c.read(postSaveTagBarProvider), isNull);
    expect(c.read(clipTagProvider('req-1'))?.id, 'handball.tag.save');
  });

  test('deleting a session closes it if active and removes its files', () async {
    await c.read(activeSessionProvider.notifier).start(name: 'T', type: SessionType.other, templateId: null);
    final id = c.read(activeSessionProvider)!.id;
    await c.read(clipStoreProvider).store('clip-1', Uint8List(4));
    await c.read(clipStoreProvider).store('clip-2', Uint8List(4));

    await deleteLibraryClips(c.read, ['clip-2']);
    expect(deleted, ['${root.path}/clips/$id/clip-2.mp4']);
    await deleteLibrarySession(c.read, id);
    expect(deleted.last, '${root.path}/clips/$id/clip-1.mp4');
    expect(c.read(activeSessionProvider), isNull);
    expect(await db.clip('clip-1'), isNull);
  });
}

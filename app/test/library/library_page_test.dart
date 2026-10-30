import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/library/data/library_database.dart';
import 'package:instant_replay/features/library/data/templates.dart';
import 'package:instant_replay/features/library/library_providers.dart';
import 'package:instant_replay/features/library/presentation/library_page.dart';
import 'package:instant_replay/features/viewer/tags/tag_widgets.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sessions → clips, filter by tag, batch delete', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = LibraryDatabase(NativeDatabase.memory());
    final deleted = <String>[];
    late SessionRow session;
    await tester.runAsync(() async {
      session = await db.createSession(name: 'League 7', type: SessionType.match, templateId: BuiltInTemplates.football);
      for (final (i, tag) in ['football.cat.attack', 'football.tag.shot', 'football.tag.goal'].indexed) {
        await db.addClip(ClipsCompanion.insert(
          id: 'c$i',
          sessionId: session.id,
          requestedAt: DateTime(2026, 10, 30, 12, i),
          durationMs: const Value(20000),
          filePath: '/f/c$i.mp4',
          sizeBytes: 10,
          createdAt: DateTime(2026, 10, 30),
          updatedAt: DateTime(2026, 10, 30),
        ));
        await db.setClipTags('c$i', [tag]);
      }
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
        libraryDatabaseProvider.overrideWithValue(db),
        clipFileDeleterProvider.overrideWithValue((paths) async => deleted.addAll(paths)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LibraryPage(),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Iterable<String> shown() => [
          for (final w in tester.widgetList<ListTile>(find.byType(ListTile)))
            if (w.key case ValueKey<String>(:final value) when value.startsWith('library-clip-')) value.substring(13),
        ];

    await settle();
    expect(find.text('League 7'), findsOneWidget);
    expect(find.textContaining('3 clips'), findsOneWidget);
    await tester.tap(find.text('League 7'));
    await settle();
    expect(shown(), ['c2', 'c1', 'c0']);
    expect(find.text('Goal · 12:02'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-filter-football.cat.attack')));
    await tester.pump();
    expect(shown(), ['c0']);
    await tester.tap(find.byKey(const ValueKey('library-filter-football.tag.goal')));
    await tester.pump();
    expect(shown(), ['c2']);
    await tester.tap(find.byKey(const ValueKey('library-filter-all')));
    await tester.pump();
    expect(shown(), ['c2', 'c1', 'c0']);

    await tester.longPress(find.byKey(const ValueKey('library-clip-c2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('library-clip-c0')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-delete-selected')));
    await settle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await settle();
    expect(deleted, unorderedEquals(['/f/c0.mp4', '/f/c2.mp4']));
    expect(shown(), ['c1']);

    // Drift closes its query streams on a timer: let it run before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });

  // The picker used to offer the active session's tags: with no session (the library opened
  // from the session picker) the web tag set good/bad/other, whose ids are no library tags; with
  // another session active, that session's template.
  for (final activeTemplate in [null, BuiltInTemplates.basketball]) {
    testWidgets("a reviewed clip is tagged from its own session's template (active: $activeTemplate)", (tester) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = LibraryDatabase(NativeDatabase.memory());
      late SessionRow session;
      await tester.runAsync(() async {
        session = await db.createSession(
          name: 'League 7',
          type: SessionType.match,
          templateId: BuiltInTemplates.football,
        );
        await db.addClip(
          ClipsCompanion.insert(
            id: 'c0',
            sessionId: session.id,
            requestId: const Value('req-0'),
            requestedAt: DateTime(2026, 10, 30, 12),
            durationMs: const Value(20000),
            filePath: '/f/c0.mp4',
            sizeBytes: 10,
            createdAt: DateTime(2026, 10, 30),
            updatedAt: DateTime(2026, 10, 30),
          ),
        );
        // A label that was a category before the merge is a tag like any other.
        await db.setClipTags('c0', ['football.cat.attack']);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
          libraryDatabaseProvider.overrideWithValue(db),
        ],
      );
      if (activeTemplate != null) {
        await tester.runAsync(
          () => container
              .read(activeSessionProvider.notifier)
              .start(name: 'Now', type: SessionType.training, templateId: activeTemplate),
        );
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SessionClipsPage(session: session),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Queried from the test zone, behind the app's own writes (a real-async query could wait
      // forever on a write left in the fake zone).
      Future<List<String>> stored() async {
        List<String>? result;
        unawaited(() async {
          result = [for (final t in await db.select(db.clipTags).get()) t.tagId];
        }());
        for (var i = 0; result == null && i < 50; i++) {
          await settle();
        }
        return result!;
      }

      await settle();
      await tester.tap(find.byKey(const ValueKey('library-clip-c0')));
      await settle();
      await tester.tap(find.byKey(const ValueKey('review-tag')));
      await settle();

      // Football's tags in one list, the current one selected; nothing from elsewhere.
      for (final id in ['football.cat.defense', 'football.tag.shot', 'football.tag.corner']) {
        expect(find.byKey(ValueKey('tag-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const ValueKey('tag-good')), findsNothing);
      expect(find.byKey(const ValueKey('tag-basketball.tag.basket')), findsNothing);
      expect(
        tester
            .widget<TagButton>(
              find.ancestor(
                of: find.byKey(const ValueKey('tag-football.cat.attack')),
                matching: find.byType(TagButton),
              ),
            )
            .selected,
        isTrue,
      );
      // One section only: no categories any more.
      expect(find.text('Category'), findsNothing);
      // The active template is not editable from a clip of another session.
      expect(find.text('Edit tags'), findsNothing);

      // The new tag replaces the old one and reaches the library.
      await tester.tap(find.byKey(const ValueKey('tag-football.tag.shot')));
      await settle();
      expect(await stored(), ['football.tag.shot']);
      expect(find.text('Shot · 12:00'), findsOneWidget); // The review's title.

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      container.dispose();
      var closed = false;
      unawaited(db.close().then((_) => closed = true));
      for (var i = 0; !closed && i < 50; i++) {
        await settle();
      }
    });
  }
}

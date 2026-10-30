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
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sessions → clips, filter by category and tag, batch delete', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = LibraryDatabase(NativeDatabase.memory());
    final deleted = <String>[];
    late SessionRow session;
    await tester.runAsync(() async {
      session = await db.createSession(name: 'League 7', type: SessionType.match, templateId: BuiltInTemplates.football);
      for (final (i, (cat, tag)) in [
        ('football.cat.attack', 'football.tag.goal'),
        ('football.cat.attack', 'football.tag.shot'),
        ('football.cat.defense', 'football.tag.goal'),
      ].indexed) {
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
        await db.setClipCategory('c$i', cat);
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
    expect(shown(), ['c1', 'c0']);
    await tester.tap(find.byKey(const ValueKey('library-filter-football.tag.goal')));
    await tester.pump();
    expect(shown(), ['c0']);
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
}

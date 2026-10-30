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
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/clip_list.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This run's clips, set by the test.
class _LiveClips extends ViewerClipsNotifier {
  _LiveClips(this.initial);

  final List<SessionClip> initial;

  @override
  List<SessionClip> build() => initial;

  void put(List<SessionClip> clips) => state = clips;
}

/// A session already open from an earlier run.
class _Active extends ActiveSessionNotifier {
  @override
  ActiveSession? build() => const ActiveSession(id: 's1', name: 'Final', type: SessionType.match, templateId: null);
}

/// The live screen's list, with the library sync it runs alongside.
class _LiveList extends ConsumerWidget {
  const _LiveList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(liveLibrarySyncProvider);
    return const ClipList();
  }
}

ClipsCompanion _row(String id, {String? requestId, required int minute}) => ClipsCompanion.insert(
      id: id,
      sessionId: 's1',
      requestId: Value(requestId),
      requestedAt: DateTime(2026, 10, 30, 12, minute),
      durationMs: const Value(20000),
      filePath: '/f/$id.mp4',
      sizeBytes: 10,
      createdAt: DateTime(2026, 10, 30),
      updatedAt: DateTime(2026, 10, 30),
    );

/// Resuming a session on Android lists the clips saved into it before (SPEC §5.1.3).
void main() {
  late LibraryDatabase db;
  late ProviderContainer container;
  final deletedFiles = <String>[];

  /// Lets drift's real futures and streams run, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Runs a query from the test zone behind the app's own writes.
  Future<T> query<T>(WidgetTester tester, Future<T> Function() run) async {
    T? result;
    var done = false;
    unawaited(run().then((v) {
      result = v;
      done = true;
    }));
    for (var i = 0; !done && i < 50; i++) {
      await settle(tester);
    }
    expect(done, isTrue, reason: 'query timed out');
    return result as T;
  }

  Future<void> pump(WidgetTester tester, {List<dynamic> overrides = const [], bool resume = true}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = LibraryDatabase(NativeDatabase.memory(), newId: () => 's1');
    deletedFiles.clear();
    await tester.runAsync(() async {
      await db.createSession(name: 'Final', type: SessionType.match, templateId: BuiltInTemplates.football);
      await db.addClip(_row('c-goal', requestId: 'r-goal', minute: 1));
      await db.setClipTags('c-goal', ['football.tag.goal']);
      // Stored without a request id (the live screen closed before it was written).
      await db.addClip(_row('c-attack', minute: 0));
      await db.setClipTags('c-attack', ['football.cat.attack']);
      // An old timestamp shows whether the screen writes the rows again.
      await db.customStatement('UPDATE clips SET updated_at = 0');
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
      libraryDatabaseProvider.overrideWithValue(db),
      clipFileDeleterProvider.overrideWithValue((paths) async => deletedFiles.addAll(paths)),
      ...overrides.cast(),
    ]);
    if (resume) {
      final row = await tester.runAsync(() => db.session('s1'));
      await tester.runAsync(() => container.read(activeSessionProvider.notifier).resume(row!));
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _LiveList()),
      ),
    ));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    var closed = false;
    unawaited(db.close().then((_) => closed = true));
    for (var i = 0; !closed && i < 50; i++) {
      await settle(tester);
    }
  }

  Iterable<String> tiles(WidgetTester tester) => [
        for (final t in tester.widgetList<ClipTile>(find.byType(ClipTile))) t.clip.requestId,
      ];

  testWidgets('the earlier clips show with their tags; a new save is not listed twice', (tester) async {
    final live = _LiveClips(const []);
    await pump(tester, overrides: [viewerClipsProvider.overrideWith(() => live)]);

    expect(tiles(tester), ['r-goal', 'c-attack']);
    expect(find.text('Goal · 12:01'), findsOneWidget);
    expect(find.text('Attack · 12:00'), findsOneWidget);
    // Tags under the same keys as this run's clips, and not written back.
    expect(container.read(clipTagsProvider), {'r-goal': 'football.tag.goal', 'c-attack': 'football.cat.attack'});
    final rows = await query(tester, () => db.select(db.clips).get());
    expect([for (final r in rows) r.updatedAt.millisecondsSinceEpoch], [0, 0]);

    // A new save: in memory first, then its library row without a request id, then with it.
    final saved = SessionClip(
      requestId: 'r-new',
      seconds: 20,
      requestedAt: DateTime(2026, 10, 30, 12, 5),
      phase: SessionClipPhase.ready,
      clipId: 'c-new',
    );
    live.put([saved]);
    await settle(tester);
    expect(tiles(tester), ['r-new', 'r-goal', 'c-attack']);
    await query(tester, () => db.addClip(_row('c-new', minute: 5)));
    await settle(tester);
    expect(tiles(tester), ['r-new', 'r-goal', 'c-attack']);
    await query(tester, () => db.updateClip('c-new', const ClipsCompanion(requestId: Value('r-new'))));
    await settle(tester);
    expect(tiles(tester), ['r-new', 'r-goal', 'c-attack']);
    // The in-memory entry is the one shown.
    expect(identical(tester.widget<ClipTile>(find.byType(ClipTile).first).clip, saved), isTrue);

    // Changing an earlier clip's tag reaches the library.
    container.read(clipTagsProvider.notifier).set('c-attack', 'football.tag.shot');
    await settle(tester);
    final entries = await query(tester, () => db.watchSessionClips('s1').first);
    expect(entries.firstWhere((e) => e.clip.id == 'c-attack').tagIds, ['football.tag.shot']);
    expect(find.text('Shot · 12:00'), findsOneWidget);

    await close(tester);
  });

  testWidgets('a tag set this run is kept over the stored one', (tester) async {
    await pump(tester, resume: false, overrides: [viewerClipsProvider.overrideWith(() => _LiveClips(const []))]);
    container.read(clipTagsProvider.notifier).set('r-goal', 'football.tag.foul');
    final row = await tester.runAsync(() => db.session('s1'));
    await tester.runAsync(() => container.read(activeSessionProvider.notifier).resume(row!));
    await settle(tester);
    expect(container.read(clipTagsProvider), {'r-goal': 'football.tag.foul', 'c-attack': 'football.cat.attack'});
    await close(tester);
  });

  testWidgets('an earlier clip swipes away with Undo, and the deletion stands without it', (tester) async {
    await pump(tester);
    expect(tiles(tester), ['r-goal', 'c-attack']);

    Future<void> step() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    await tester.drag(find.text('Goal · 12:01'), const Offset(-600, 0));
    await step();
    expect(tiles(tester), ['c-attack']);
    expect(find.text('Goal · 12:01 deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await step();
    await settle(tester);
    expect(tiles(tester), ['r-goal', 'c-attack']);
    expect(deletedFiles, isEmpty);

    await tester.drag(find.text('Goal · 12:01'), const Offset(-600, 0));
    await step();
    await tester.pump(const Duration(seconds: 10));
    await step();
    await settle(tester);
    expect(tiles(tester), ['c-attack']);
    expect(await query(tester, () => db.clip('c-goal')), isNull);
    expect(deletedFiles, ['/f/c-goal.mp4']);
    expect(container.read(clipTagsProvider).containsKey('r-goal'), isFalse);

    await close(tester);
  });

  testWidgets('web keeps the session in memory only and never opens the library', (tester) async {
    final live = _LiveClips([
      SessionClip(requestId: 'r1', seconds: 20, requestedAt: DateTime(2026, 10, 30, 12, 3), phase: SessionClipPhase.ready),
    ]);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        capabilitiesProvider.overrideWithValue(Capabilities.web),
        libraryDatabaseProvider.overrideWith((_) => throw StateError('no library on web')),
        activeSessionProvider.overrideWith(_Active.new),
        viewerClipsProvider.overrideWith(() => live),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _LiveList()),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tiles(tester), ['r1']);
  });
}

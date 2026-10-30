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
import 'package:instant_replay/features/library/presentation/session_picker_view.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/live_control_view.dart';
import 'package:instant_replay/features/viewer/viewer_page.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paired extends ViewerSetupNotifier {
  @override
  ViewerSetup build() => ViewerSetup(base: Uri.parse('http://10.0.0.2:8080'), token: 't');
}

class _ConnectedLink extends LinkStateNotifier {
  @override
  LinkState? build() => const LinkState(
        phase: LinkPhase.connected,
        camera: CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
        status: CameraStatus(recording: true, fps: 30, bufferMs: 60000, outboxClips: 0, thermalStatus: 0),
      );
}

class _PlayingLive extends LiveViewNotifier {
  @override
  LiveViewState build() => const LiveViewState(phase: LivePhase.playing);
}

class _Clips extends ViewerClipsNotifier {
  int n = 0;

  @override
  List<SessionClip> build() => const [];

  @override
  String? save({int? seconds}) => 'r${++n}';
}

void main() {
  late LibraryDatabase db;

  Future<Widget> app() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = LibraryDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
        libraryDatabaseProvider.overrideWithValue(db),
        viewerSetupProvider.overrideWith(_Paired.new),
        linkStateProvider.overrideWith(_ConnectedLink.new),
        liveViewProvider.overrideWith(_PlayingLive.new),
        viewerClipsProvider.overrideWith(_Clips.new),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ViewerPage(),
      ),
    );
  }

  /// Lets drift's real futures and streams run, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Android: pick a session first, then the live screen offers its template', (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app());
    await settle(tester);
    expect(find.byType(SessionPickerView), findsOneWidget);
    expect(find.byType(LiveControlView), findsNothing);
    expect(find.byKey(const ValueKey('session-continue')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('session-name')), 'Cup final');
    await tester.tap(find.byKey(const ValueKey('session-template-${BuiltInTemplates.generic}')));
    await settle(tester);
    await tester.tap(find.text('Handball').last);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('session-start')));
    await settle(tester);

    expect(find.byType(LiveControlView), findsOneWidget);
    final session = (await tester.runAsync(db.latestSession))!;
    expect((session.name, session.type, session.templateId), ('Cup final', SessionType.match, BuiltInTemplates.handball));

    // The tag bar shows the handball categories and tags; tagging is in memory, never blocking.
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await settle(tester);
    expect(find.text('Set piece'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-handball.cat.attack')));
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await settle(tester);
    // Categories come first; the row scrolls to the tags.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('tag-handball.tag.goal')),
      find.byKey(const ValueKey('viewer-tag-bar')),
      const Offset(-200, 0),
    );
    await tester.tap(find.byKey(const ValueKey('tag-handball.tag.goal')));
    await settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(ViewerPage)));
    expect(container.read(clipCategoriesProvider), {'r1': 'handball.cat.attack'});
    expect(container.read(clipTagsProvider), {'r2': 'handball.tag.goal'});
    await tester.pump(PostSaveTagBarNotifier.visibleFor);

    // Change session from the menu: back to the picker, which now offers to continue.
    await tester.tap(find.byKey(const ValueKey('viewer-menu')));
    await settle(tester);
    await tester.tap(find.text('Change session'));
    await settle(tester);
    expect(find.byType(SessionPickerView), findsOneWidget);
    expect(find.text('Cup final'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-continue')));
    await settle(tester);
    expect(find.byType(LiveControlView), findsOneWidget);
    expect(container.read(activeSessionProvider)?.id, session.id);
  });
}

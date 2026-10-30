import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/clip_list.dart';
import 'package:instant_replay/features/viewer/ui/live_control_view.dart';
import 'package:instant_replay/features/viewer/viewer_page.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ConnectedLink extends LinkStateNotifier {
  @override
  LinkState? build() => const LinkState(
        phase: LinkPhase.connected,
        camera: CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
        status: CameraStatus(recording: true, fps: 30, bufferMs: 60000, outboxClips: 0, thermalStatus: 0),
      );
}

class _RecordingClips extends ViewerClipsNotifier {
  _RecordingClips(this.saved, [this.clips = const []]);

  final List<int?> saved;
  final List<SessionClip> clips;

  @override
  List<SessionClip> build() => clips;

  @override
  String? save({int? seconds}) {
    saved.add(seconds);
    return 'r${saved.length}';
  }
}

class _PlayingLive extends LiveViewNotifier {
  @override
  LiveViewState build() => const LiveViewState(phase: LivePhase.playing);
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget _app(Widget child, List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

/// Lets AnimatedSwitcher start and finish its 300 ms fade.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('big button saves the default preset; chips save their own duration', (tester) async {
    final saved = <int?>[];
    await tester.pumpWidget(_app(const SaveControls(), [
      sharedPreferencesProvider.overrideWithValue(await _prefs()),
      linkStateProvider.overrideWith(_ConnectedLink.new),
      viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
    ]));
    expect(find.text('SAVE 20 s'), findsOneWidget);
    expect(find.text('10 s'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('60 s'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('viewer-save'))).height, greaterThanOrEqualTo(56));

    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await tester.tap(find.text('30 s'));
    await tester.tap(find.text('10 s'));
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    expect(saved, [null, 30, 10, null]);
    await tester.pump(PostSaveTagBarNotifier.visibleFor);
  });

  testWidgets('after a save the tag bar tags that clip, and a new save replaces the bar', (tester) async {
    final saved = <int?>[];
    late WidgetRef ref;
    await tester.pumpWidget(_app(Consumer(builder: (context, r, _) {
      ref = r;
      return const SaveControls();
    }), [
      sharedPreferencesProvider.overrideWithValue(await _prefs()),
      linkStateProvider.overrideWith(_ConnectedLink.new),
      viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
    ]));
    final bar = find.byKey(const ValueKey('viewer-tag-bar'));
    expect(bar, findsNothing);

    await tester.tap(find.byKey(const ValueKey('viewer-save'))); // r1
    await _settle(tester);
    expect(bar, findsOneWidget);
    // The chips stay usable while the bar is up.
    await tester.tap(find.text('30 s')); // r2
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('tag-${TagsNotifier.bad}')));
    await _settle(tester);
    expect(ref.read(clipTagsProvider), {'r2': TagsNotifier.bad});
    expect(bar, findsNothing);

    // Untouched, the bar fades after ~6 s.
    await tester.tap(find.byKey(const ValueKey('viewer-save'))); // r3
    await _settle(tester);
    expect(bar, findsOneWidget);
    await tester.pump(PostSaveTagBarNotifier.visibleFor);
    await _settle(tester);
    expect(bar, findsNothing);
    expect(ref.read(clipTagsProvider), {'r2': TagsNotifier.bad});
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(768, 1024), Size(1280, 800)]) {
    testWidgets('live screen fits ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final clips = [
        for (var i = 0; i < 12; i++)
          SessionClip(
            requestId: 'r$i',
            seconds: 20,
            requestedAt: DateTime(2026, 10, 29, 12, i),
            phase: SessionClipPhase.values[i % SessionClipPhase.values.length],
          ),
      ];
      // Leave room for the 48 px app bar of the paired Viewer.
      await tester.pumpWidget(_app(const Column(children: [SizedBox(height: 48), Expanded(child: LiveControlView())]), [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        linkStateProvider.overrideWith(_ConnectedLink.new),
        liveViewProvider.overrideWith(_PlayingLive.new),
        viewerClipsProvider.overrideWith(() => _RecordingClips([], clips)),
      ]));
      await tester.tap(find.byKey(const ValueKey('viewer-save')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('viewer-tag-bar')), findsOneWidget);
      final save = tester.getRect(find.byKey(const ValueKey('viewer-save')));
      expect(save.height, greaterThanOrEqualTo(56));
      expect(save.bottom, lessThanOrEqualTo(size.height));
      expect(find.text('Clip · 12:00'), findsOneWidget);
      await tester.pump(PostSaveTagBarNotifier.visibleFor);
      await _settle(tester);
    });
  }

  testWidgets('phone landscape keeps clip rows visible with filter chips and the tag bar', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clips = [
      for (var i = 0; i < 6; i++)
        SessionClip(
          requestId: 'r$i',
          seconds: 20,
          requestedAt: DateTime(2026, 10, 29, 12, i),
          phase: SessionClipPhase.ready,
        ),
    ];
    await tester.pumpWidget(_app(const Column(children: [SizedBox(height: 48), Expanded(child: LiveControlView())]), [
      sharedPreferencesProvider.overrideWithValue(await _prefs()),
      linkStateProvider.overrideWith(_ConnectedLink.new),
      liveViewProvider.overrideWith(_PlayingLive.new),
      viewerClipsProvider.overrideWith(() => _RecordingClips([], clips)),
    ]));
    final ref = ProviderScope.containerOf(tester.element(find.byType(LiveControlView)));
    ref.read(clipTagsProvider.notifier)
      ..set('r0', TagsNotifier.good)
      ..set('r1', TagsNotifier.bad);
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('filter-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-tag-bar')), findsOneWidget);
    // At least one full clip row and part of the next stay on screen.
    final rows = find.byType(ClipTile);
    expect(rows, findsAtLeast(2));
    expect(tester.getRect(rows.first).bottom, lessThanOrEqualTo(360));
    await tester.pump(PostSaveTagBarNotifier.visibleFor);
    await _settle(tester);
    // With the tag bar gone, the quick chips are back in its place.
    expect(find.byKey(const ValueKey('viewer-save-30')), findsOneWidget);
  });

  testWidgets('save is disabled while not connected', (tester) async {
    final saved = <int?>[];
    await tester.pumpWidget(_app(const SaveControls(), [
      sharedPreferencesProvider.overrideWithValue(await _prefs()),
      linkStateProvider.overrideWith(() => _NullLink()),
      viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
    ]));
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    expect(saved, isEmpty);
  });

  testWidgets('Android without a camera asks for the address, then the code', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_app(const ViewerPage(), [
      sharedPreferencesProvider.overrideWithValue(prefs),
      pageUriProvider.overrideWithValue(null),
    ]));
    expect(find.text('Connect to the camera'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.1.20');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code shown on the camera'), findsOneWidget);
    expect(find.text('Camera at http://192.168.1.20:8080'), findsOneWidget);
  });
}

class _NullLink extends LinkStateNotifier {
  @override
  LinkState? build() => null;
}

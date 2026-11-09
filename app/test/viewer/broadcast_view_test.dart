import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/broadcast/broadcast_widgets.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/ui/live_control_view.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _board = ScoreboardState(
  home: TeamState(name: 'CDM', score: 2, color: 0xFF1E88E5),
  away: TeamState(name: 'RIV', score: 1, color: 0xFFFAFAFA),
  period: 2,
  clockMs: 61000,
);

const _info = BroadcastInfo(
  state: BroadcastStreamState.live,
  configured: true,
  server: BroadcastInfo.defaultServer,
  keyHint: 'WXYZ',
  targetKbps: 4500,
  audio: true,
  bitrateKbps: 4300,
  uptimeMs: 3723000,
);

/// A Camera in broadcast mode.
class _BroadcastLink extends LinkStateNotifier {
  _BroadcastLink({this.board = _board, this.info = _info});

  final ScoreboardState? board;
  final BroadcastInfo? info;

  @override
  LinkState? build() => LinkState(
        phase: LinkPhase.connected,
        camera: const CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
        status: CameraStatus(
          recording: true,
          fps: 30,
          bufferMs: 60000,
          outboxClips: 0,
          thermalStatus: 0,
          scoreboard: board,
          broadcast: info,
        ),
      );
}

class _NoLive extends LiveViewNotifier {
  @override
  LiveViewState build() => const LiveViewState(phase: LivePhase.playing);
}

class _NoClips extends ViewerClipsNotifier {
  @override
  List<SessionClip> build() => const [];
}

/// Records what the controls send.
class _FakeBroadcast extends ViewerBroadcastNotifier {
  final sent = <Object>[];

  @override
  BroadcastNotice? build() => null;

  @override
  bool command(ScoreboardCommand command) {
    sent.add(command);
    return true;
  }

  @override
  bool configure({required String server, String? key, required int targetKbps, required bool audio}) {
    sent.add((server: server, key: key, targetKbps: targetKbps, audio: audio));
    return true;
  }

  @override
  bool start() {
    sent.add('start');
    return true;
  }

  @override
  bool stop() {
    sent.add('stop');
    return true;
  }
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

Future<_FakeBroadcast> _pump(WidgetTester tester, {LinkStateNotifier Function()? link, Size size = const Size(1280, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final remote = _FakeBroadcast();
  await tester.pumpWidget(_app(const Column(children: [SizedBox(height: 48), Expanded(child: LiveControlView())]), [
    sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
    linkStateProvider.overrideWith(link ?? _BroadcastLink.new),
    liveViewProvider.overrideWith(_NoLive.new),
    viewerClipsProvider.overrideWith(_NoClips.new),
    viewerBroadcastNoticeProvider.overrideWith(() => remote),
  ]));
  await tester.pump();
  return remote;
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('hidden in replay mode', (tester) async {
    await _pump(tester, link: () => _BroadcastLink(board: null, info: null));
    expect(_key('viewer-scoreboard'), findsNothing);
    expect(_key('viewer-broadcast'), findsNothing);
    expect(_key('viewer-save'), findsOneWidget);
  });

  testWidgets('shows the score, clock, period and stream; buttons send commands', (tester) async {
    final remote = await _pump(tester);
    expect(find.text('CDM'), findsOneWidget);
    expect(tester.widget<Text>(_key('score-home')).data, '2');
    expect(tester.widget<Text>(_key('score-away')).data, '1');
    expect(find.text('01:01'), findsOneWidget);
    expect(find.text('2H'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('4.3 Mbps · 1:02:03'), findsOneWidget);
    expect(_key('viewer-save'), findsOneWidget, reason: 'clips keep working');

    await tester.tap(_key('score-home-plus'));
    await tester.tap(_key('score-away-minus'));
    await tester.tap(_key('score-clock-toggle'));
    await tester.tap(_key('score-menu'));
    await tester.pumpAndSettle();
    await tester.tap(_key('score-visible'));
    await tester.pumpAndSettle();
    expect(remote.sent, [
      isA<ScoreCommand>().having((c) => (c.team, c.delta), 'team, delta', (Team.home, 1)),
      isA<ScoreCommand>().having((c) => (c.team, c.delta), 'team, delta', (Team.away, -1)),
      isA<ClockStartCommand>(),
      isA<VisibleCommand>().having((c) => c.visible, 'visible', false),
    ]);
  });

  testWidgets('the + and − buttons are big and apart', (tester) async {
    await _pump(tester);
    for (final team in ['home', 'away']) {
      final plus = tester.getRect(_key('score-$team-plus'));
      final minus = tester.getRect(_key('score-$team-minus'));
      expect(plus.height, greaterThanOrEqualTo(56));
      expect(minus.height, greaterThanOrEqualTo(44));
      expect((plus.center - minus.center).distance, greaterThan(100));
    }
  });

  testWidgets('a tap on the clock only hints; a long press opens the wheels', (tester) async {
    final remote = await _pump(tester);
    await tester.tap(_key('score-clock'));
    await tester.pump();
    expect(find.text('Press and hold the clock to set it'), findsOneWidget);
    expect(_key('score-clock-set'), findsNothing);

    await tester.longPress(_key('score-clock'));
    await tester.pumpAndSettle();
    // Starts at the current 01:01; one row up on the minutes, two down on the seconds.
    await tester.drag(_key('score-clock-minutes'), const Offset(0, -56));
    await tester.pumpAndSettle();
    await tester.drag(_key('score-clock-seconds'), const Offset(0, 112));
    await tester.pumpAndSettle();
    await tester.tap(_key('score-clock-set'));
    await tester.pumpAndSettle();
    expect(remote.sent.single, isA<ClockSetCommand>().having((c) => c.ms, 'ms', (2 * 60 + 59) * 1000));
  });

  testWidgets('period changes live in the menu and ask first', (tester) async {
    final remote = await _pump(tester);
    await tester.tap(_key('score-menu'));
    await tester.pumpAndSettle();
    expect(_key('score-period-next'), findsNothing, reason: 'already in the last period');
    await tester.tap(_key('score-period-prev'));
    await tester.pumpAndSettle();
    expect(remote.sent, isEmpty);
    await tester.tap(_key('score-period-confirm'));
    await tester.pumpAndSettle();
    expect(remote.sent.single, isA<PeriodCommand>().having((c) => c.delta, 'delta', -1));
  });

  testWidgets('reset and stop ask first', (tester) async {
    final remote = await _pump(tester);
    await tester.tap(_key('score-menu'));
    await tester.pumpAndSettle();
    await tester.tap(_key('score-reset'));
    await tester.pumpAndSettle();
    expect(remote.sent, isEmpty);
    await tester.tap(_key('score-reset-confirm'));
    await tester.pumpAndSettle();
    expect(remote.sent.single, isA<ResetCommand>());

    await tester.tap(_key('viewer-broadcast-stop'));
    await tester.pumpAndSettle();
    await tester.tap(_key('broadcast-stop-keep'));
    await tester.pumpAndSettle();
    expect(remote.sent, hasLength(1));
    await tester.tap(_key('viewer-broadcast-stop'));
    await tester.pumpAndSettle();
    await tester.tap(_key('broadcast-stop-confirm'));
    await tester.pumpAndSettle();
    expect(remote.sent.last, 'stop');
  });

  testWidgets('settings: names, colours, periods, minutes and direction', (tester) async {
    final remote = await _pump(tester);
    await tester.tap(_key('score-menu'));
    await tester.pumpAndSettle();
    await tester.tap(_key('score-settings'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('score-settings-home-name'), 'lions');
    await tester.tap(_key('score-settings-away-color-4'));
    await tester.tap(find.text('4'));
    await tester.enterText(_key('score-settings-minutes'), '10');
    await tester.tap(find.text('Counts down'));
    await tester.pumpAndSettle();
    await tester.tap(_key('score-settings-save'));
    await tester.pumpAndSettle();
    final s = (remote.sent.single as SettingsCommand).settings;
    expect((s.homeName, s.awayName, s.awayColor, s.periods, s.periodMs, s.countDown),
        ('LIONS', 'RIV', teamPalette[4], 4, 600000, true));
  });

  testWidgets('stream settings: an empty key keeps the stored one', (tester) async {
    final remote = await _pump(tester, link: () => _BroadcastLink(
          info: const BroadcastInfo(
            state: BroadcastStreamState.idle,
            configured: true,
            server: BroadcastInfo.defaultServer,
            keyHint: 'WXYZ',
            targetKbps: 4500,
            audio: true,
          ),
        ));
    expect(find.text('Ready · 4500 kbps'), findsOneWidget);
    await tester.tap(_key('viewer-broadcast-settings'));
    await tester.pumpAndSettle();
    expect(find.text('Leave empty to keep •••• WXYZ'), findsOneWidget);
    await tester.tap(_key('broadcast-audio'));
    await tester.tap(_key('broadcast-config-save'));
    await tester.pumpAndSettle();
    expect(remote.sent.single, (server: BroadcastInfo.defaultServer, key: null, targetKbps: 4500, audio: false));

    await tester.tap(_key('viewer-broadcast-start'));
    expect(remote.sent.last, 'start');
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(768, 1024), Size(1280, 800), Size(800, 1280)]) {
    testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
      await _pump(tester, size: size);
      expect(tester.takeException(), isNull);
      for (final k in ['score-home-plus', 'score-away-plus', 'score-clock-toggle', 'viewer-broadcast-stop', 'viewer-save']) {
        final r = tester.getRect(_key(k));
        expect(r.bottom, lessThanOrEqualTo(size.height), reason: k);
        expect(r.right, lessThanOrEqualTo(size.width), reason: k);
        expect(r.height, greaterThanOrEqualTo(47.9), reason: k);
      }
    });
  }
}

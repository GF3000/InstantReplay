import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/broadcast/scoreboard_controller.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show OverlayState;
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late int now;
  late List<OverlayState> overlays;
  var language = 'en';

  ScoreboardController controller() => ScoreboardController(
        prefs: prefs,
        clockMs: () => now,
        setOverlay: (o) async => overlays.add(o),
        l10n: () => lookupAppLocalizations(Locale(language)),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = 1000;
    overlays = [];
    language = 'en';
  });

  test('starts from the initial board', () {
    final c = controller();
    expect(c.current, ScoreboardState.initial);
  });

  test('commands apply and re-anchor; a running clock advances with the monotonic clock', () {
    final c = controller()..apply(const ClockStartCommand());
    expect(c.current.clockRunning, isTrue);
    now += 5000;
    expect(c.current.clockMs, 5000);

    c.apply(const ScoreCommand(team: Team.home, delta: 1));
    expect(c.state.clockMs, 5000, reason: 'anchored at the command');
    expect(c.state.home.score, 1);
    now += 1500;
    expect(c.current.clockMs, 6500);

    c.apply(const ClockPauseCommand());
    now += 10000;
    expect(c.current.clockMs, 6500);
    expect(c.current.clockRunning, isFalse);

    c
      ..apply(const ScoreCommand(team: Team.away, delta: 1))
      ..apply(const ScoreCommand(team: Team.away, delta: -1))
      ..apply(const ScoreCommand(team: Team.away, delta: -1));
    expect(c.current.away.score, 0, reason: 'never below 0');
  });

  test('a count-down clock stops at 0', () {
    final c = controller()
      ..apply(const SettingsCommand(ScoreboardSettings(
        homeName: 'a',
        awayName: 'b',
        homeColor: 1,
        awayColor: 2,
        periods: 4,
        periodMs: 60000,
        countDown: true,
      )));
    expect(c.current.clockMs, 60000);
    expect(c.current.home.name, 'A');
    c.apply(const ClockStartCommand());
    now += 70000;
    expect(c.current.clockMs, 0);
    expect(c.current.clockRunning, isFalse);
  });

  test('changes are emitted with the new state', () async {
    final c = controller();
    final next = c.changes.first;
    c.apply(const ScoreCommand(team: Team.home, delta: 1));
    expect((await next).home.score, 1);
  });

  test('every command is saved; a restart restores it with the clock paused at its saved value', () {
    final c = controller()
      ..apply(const ScoreCommand(team: Team.home, delta: 1))
      ..apply(const ScoreCommand(team: Team.home, delta: 1))
      ..apply(const PeriodCommand(delta: 1))
      ..apply(const ClockStartCommand());
    now += 3000;
    c.apply(const ScoreCommand(team: Team.away, delta: 1));
    now += 2000;

    final saved = ScoreboardState.fromJson(jsonDecode(prefs.getString(ScoreboardController.storageKey)!) as Json);
    expect(saved.clockMs, 3000);

    now = 50; // A new process: the monotonic clock starts over.
    final restored = controller().current;
    expect(restored.home.score, 2);
    expect(restored.away.score, 1);
    expect(restored.period, 2);
    expect(restored.clockMs, 3000);
    expect(restored.clockRunning, isFalse);
  });

  test('dispose saves the clock as it is now', () {
    final c = controller()..apply(const ClockStartCommand());
    now += 42000;
    c.dispose();
    expect(controller().current.clockMs, 42000);
  });

  test('a corrupt saved board falls back to the initial one', () async {
    SharedPreferences.setMockInitialValues({ScoreboardController.storageKey: '{nope'});
    prefs = await SharedPreferences.getInstance();
    expect(controller().current, ScoreboardState.initial);
  });

  group('overlay', () {
    test('only while enabled; enabling pushes the current board, then every change', () async {
      final c = controller()..apply(const ScoreCommand(team: Team.home, delta: 1));
      expect(overlays, isEmpty);

      c.overlayEnabled = true;
      expect(overlays, hasLength(1));
      c.apply(const ScoreCommand(team: Team.away, delta: 1));
      expect(overlays, hasLength(2));

      final o = overlays.last;
      expect(o.visible, isTrue);
      expect(o.homeName, 'LOC');
      expect(o.awayName, 'VIS');
      expect(o.homeScore, 1);
      expect(o.awayScore, 1);
      expect(o.homeColor, ScoreboardState.initial.home.color);
      expect(o.awayColor, ScoreboardState.initial.away.color);
      expect(o.periodLabel, '1H');
      expect(o.clockMs, 0);
      expect(o.clockRunning, isFalse);
      expect(o.countDown, isFalse);

      c.overlayEnabled = false;
      c.apply(const VisibleCommand(visible: false));
      expect(overlays, hasLength(2));
    });

    test('carries the clock value now and the visibility', () {
      final c = controller()
        ..overlayEnabled = true
        ..apply(const ClockStartCommand());
      now += 61000;
      c.apply(const VisibleCommand(visible: false));
      expect(overlays.last.clockMs, 61000);
      expect(overlays.last.clockRunning, isTrue);
      expect(overlays.last.visible, isFalse);
    });

    test('period labels follow the number of periods and the language', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final es = lookupAppLocalizations(const Locale('es'));
      expect(periodLabel(en, period: 1, periods: 2), '1H');
      expect(periodLabel(en, period: 2, periods: 2), '2H');
      expect(periodLabel(es, period: 1, periods: 2), '1T');
      expect(periodLabel(es, period: 2, periods: 2), '2T');
      expect(periodLabel(es, period: 3, periods: 4), 'Q3');
      expect(periodLabel(en, period: 4, periods: 4), 'Q4');
      expect(periodLabel(en, period: 2, periods: 3), 'P2');
      expect(periodLabel(es, period: 1, periods: 1), '');
    });

    test('uses the Camera language when pushed', () {
      language = 'es';
      controller().overlayEnabled = true;
      expect(overlays.last.periodLabel, '1T');
    });
  });
}

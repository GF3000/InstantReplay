import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/broadcast/broadcast_host.dart';
import 'package:instant_replay/features/broadcast/replay_controller.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show ReplayStatus;

import '../camera/fake_capture_layer.dart';

void main() {
  late FakeCaptureLayer capture;
  late ReplayController replay;
  late int nowMs;
  late bool live;
  late String language;
  late int changes;
  late List<String> failures;
  late bool scoreboardOnReplays;

  setUp(() {
    capture = FakeCaptureLayer();
    nowMs = 0;
    live = true;
    language = 'en';
    changes = 0;
    failures = [];
    scoreboardOnReplays = false;
    replay = ReplayController(
      capture: capture,
      clockMs: () => nowMs,
      l10n: () => lookupAppLocalizations(Locale(language)),
      isLive: () => live,
      replayScoreboard: () => scoreboardOnReplays,
    );
    replay.changes.listen((_) => changes++);
    replay.failures.listen(failures.add);
  });

  tearDown(() => replay.dispose());

  test('speeds go to the nearest one offered', () {
    expect(ReplayController.nearestSpeed(0.25), 0.25);
    expect(ReplayController.nearestSpeed(0.3), 0.25);
    expect(ReplayController.nearestSpeed(0.4), 0.5);
    expect(ReplayController.nearestSpeed(0.8), 1.0);
    expect(ReplayController.nearestSpeed(2), 1.0);
    expect(ReplayController.nearestSpeed(0), 0.25);
    expect(ReplayController.nearestSpeed(-3), 0.25);
    expect(ReplayController.nearestSpeed(double.nan), 1.0);
  });

  test('the scoreboard over a replay follows the stream setting, read at each start (off by default)', () async {
    await replay.air('clip1');
    scoreboardOnReplays = true;
    await replay.air('clip2');
    expect(capture.replayScoreboards, [false, true]);
  });

  test('the label on air follows the Camera language', () async {
    await replay.air('clip1');
    language = 'es';
    await replay.air('clip2', speed: 0.7);
    expect(capture.replayLabels, ['REPLAY', 'REPETICIÓN']);
    expect(capture.calls.where((c) => c.startsWith('replayStart')), ['replayStart:clip1:1.0', 'replayStart:clip2:0.5']);
  });

  test('a replay on air advances at its speed and stops at the end', () async {
    await replay.air('clip1', speed: 0.5);
    await pumpEventQueue();
    expect(changes, 1, reason: 'one change for one start');
    expect(replay.current!.positionMs, 0);
    nowMs = 3000;
    expect(replay.current!.positionMs, 1500);
    // Where the plugin's media clock is too; its speed event carries it.
    capture.replayState = ReplayStatus(clipId: 'clip1', speed: 0.5, positionMs: 1500, durationMs: 20000);
    await replay.setSpeed(1);
    await pumpEventQueue();
    expect(changes, 2);
    expect((replay.current!.speed, replay.current!.positionMs), (1.0, 1500), reason: 'the position stays');
    nowMs = 4000;
    expect(replay.current!.positionMs, 2500);
    nowMs = 60000;
    expect(replay.current!.positionMs, 20000);

    // The stats re-anchor the position without a change.
    capture.statsController.add(
      stats(replay: ReplayStatus(clipId: 'clip1', speed: 1, positionMs: 7000, durationMs: 20000)),
    );
    await pumpEventQueue();
    expect(replay.current!.positionMs, 7000);
    expect(changes, 2);
  });

  test('the end of the clip, a stop or a failure clears it', () async {
    await replay.air('clip1');
    capture.endReplay();
    await pumpEventQueue();
    expect(replay.current, isNull);
    expect(changes, 2);

    await replay.air('clip2');
    await replay.stop();
    await pumpEventQueue();
    expect(replay.current, isNull);
    expect(capture.calls.last, 'replayStop');

    await replay.air('clip3');
    capture.endReplay(error: 'decoder died');
    await pumpEventQueue();
    expect(replay.current, isNull);
    expect(failures, ['decoder died']);
  });

  test('replacing a replay keeps the new one on air', () async {
    await replay.air('clip1');
    await replay.air('clip2');
    await pumpEventQueue();
    expect(replay.current!.clipId, 'clip2');
  });

  test('a replay the plugin stopped reporting is taken as ended', () async {
    await replay.air('clip1');
    capture.statsController.add(stats());
    await pumpEventQueue();
    expect(replay.current, isNotNull, reason: 'a stats tick may lag behind the start');
    nowMs = ReplayController.staleMs + 1;
    capture.statsController.add(stats());
    await pumpEventQueue();
    expect(replay.current, isNull);
  });

  test('refusals: not_live without a stream; native codes kept, others replay_failed', () async {
    live = false;
    await expectLater(
      replay.air('clip1'),
      throwsA(isA<BroadcastException>().having((e) => e.code, 'code', 'not_live')),
    );
    expect(capture.calls, isEmpty);

    live = true;
    capture.replayStartError = PlatformException(code: 'replay_unavailable');
    await expectLater(
      replay.air('clip1'),
      throwsA(isA<BroadcastException>().having((e) => e.code, 'code', 'replay_unavailable')),
    );
    capture.replayStartError = PlatformException(code: 'weird', message: 'boom');
    await expectLater(
      replay.air('clip1'),
      throwsA(isA<BroadcastException>().having((e) => (e.code, e.message), 'code', ('replay_failed', 'boom'))),
    );
    expect(replay.current, isNull);
  });

  test('speed and stop without a replay do nothing', () async {
    await replay.setSpeed(0.5);
    await replay.stop();
    await pumpEventQueue();
    expect(capture.calls, isEmpty);
    expect(changes, 0);
  });
}

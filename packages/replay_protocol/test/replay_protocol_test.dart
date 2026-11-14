import 'package:replay_protocol/replay_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('exposes protocol constants', () {
    expect(protocolVersion, 1);
    expect(serviceType, '_instantreplay._tcp');
    expect(Api.clip('abc'), '/api/v1/clips/abc');
    expect(Api.ack('abc'), '/api/v1/clips/abc/ack');
  });

  group('models', () {
    test('ClipDto round-trips and omits null fields', () {
      const clip = ClipDto(id: 'c1', requestId: 'r1', state: ClipState.recording, createdAtMs: 42);
      expect(clip.toJson(), {'id': 'c1', 'requestId': 'r1', 'state': 'recording', 'createdAtMs': 42});
      const ready = ClipDto(
        id: 'c1',
        requestId: 'r1',
        state: ClipState.ready,
        createdAtMs: 42,
        requestedBy: 'v1',
        bytes: 100,
        durationMs: 13000,
        sha256: 'ab',
      );
      expect(ClipDto.fromJson(ready.toJson()), ready);
    });

    test('SaveClipRequest defaults the post-roll and accepts ints', () {
      final r = SaveClipRequest.fromJson({'requestId': 'r', 'preSeconds': 20});
      expect(r.preSeconds, 20.0);
      expect(r.postSeconds, 2.0);
    });

    test('CameraStatus round-trips', () {
      const s = CameraStatus(recording: true, fps: 30, bufferMs: 80000, outboxClips: 2, thermalStatus: 1, plugged: true);
      final back = CameraStatus.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(back.sessionRecording, isNull);
      expect(s.toJson().containsKey('sessionRecording'), isFalse);
    });

    test('CameraStatus round-trips the full-session recording', () {
      const s = CameraStatus(
        recording: true,
        fps: 30,
        bufferMs: 80000,
        outboxClips: 0,
        thermalStatus: 0,
        sessionRecording: SessionRecording(
          state: SessionRecordingState.paused,
          elapsedMs: 2820000,
          parts: 2,
          freeBytes: 12000000000,
          lowSpace: true,
          remainingMs: 540000,
        ),
      );
      final json = s.toJson();
      expect(json['sessionRecording'], {
        'state': 'paused',
        'elapsedMs': 2820000,
        'parts': 2,
        'freeBytes': 12000000000,
        'lowSpace': true,
        'remainingMs': 540000,
      });
      final r = CameraStatus.fromJson(json).sessionRecording!;
      expect((r.state, r.elapsedMs, r.parts, r.freeBytes, r.lowSpace, r.remainingMs),
          (SessionRecordingState.paused, 2820000, 2, 12000000000, true, 540000));
    });

    test('SessionRecording without remainingMs, and an unknown state reads as idle', () {
      const r = SessionRecording(state: SessionRecordingState.idle, elapsedMs: 0, parts: 0, freeBytes: 1, lowSpace: false);
      expect(r.toJson().containsKey('remainingMs'), isFalse);
      expect(SessionRecording.fromJson(r.toJson()).remainingMs, isNull);
      final future = SessionRecording.fromJson({...r.toJson(), 'state': 'uploading'});
      expect(future.state, SessionRecordingState.idle);
    });

    test('a status from an older Camera has no full-session recording', () {
      final old = CameraStatus.fromJson(
          {'recording': true, 'fps': 30, 'bufferMs': 1000, 'outboxClips': 0, 'thermalStatus': 0, 'plugged': false});
      expect(old.sessionRecording, isNull);
      expect(old.plugged, isFalse);
    });
  });

  group('messages', () {
    final samples = <WsMessage>[
      const Hello(protocolVersion: 1, viewerId: 'v1'),
      const Welcome(camera: CameraInfo(protocolVersion: 1, cameraId: 'cam', name: 'Redmi', profileId: '1080p30')),
      const LiveStart(codec: 'VP8'),
      const LiveStop(),
      const RtcOffer(sdp: 'v=0'),
      const RtcAnswer(sdp: 'v=0'),
      const RtcIce(candidate: 'candidate:1 1 udp 1 192.168.1.2 5000 typ host', sdpMid: '0', sdpMLineIndex: 0),
      const ClipChanged(clip: ClipDto(id: 'c', requestId: 'r', state: ClipState.ready, createdAtMs: 1)),
      const StatusUpdate(status: CameraStatus(recording: true, fps: 30, bufferMs: 1, outboxClips: 0, thermalStatus: 0)),
      const ErrorMessage(code: 'not_running', message: 'Capture is not running'),
      const RecStart(),
      const RecStart(includeSeconds: 30),
      const RecPause(),
      const RecStop(),
      const RecordingFinished(name: 'InstantReplay_2026-10-30_11-30.mp4', parts: 2, durationMs: 2820000, reason: RecordingEndReason.lowSpace),
      const StatusUpdate(
        status: CameraStatus(
          recording: true,
          fps: 30,
          bufferMs: 1,
          outboxClips: 0,
          thermalStatus: 0,
          sessionRecording: SessionRecording(
              state: SessionRecordingState.recording, elapsedMs: 5000, parts: 1, freeBytes: 9, lowSpace: false),
        ),
      ),
      const StatusUpdate(
        status: CameraStatus(
          recording: true,
          fps: 30,
          bufferMs: 1,
          outboxClips: 0,
          thermalStatus: 0,
          scoreboard: ScoreboardState.initial,
          broadcast: BroadcastInfo(
            state: BroadcastStreamState.live,
            configured: true,
            server: BroadcastInfo.defaultServer,
            targetKbps: 4500,
            audio: true,
            keyHint: 'ab12',
            bitrateKbps: 4400,
            uptimeMs: 60000,
          ),
        ),
      ),
      const ScoreboardCmd(ScoreCommand(team: Team.away, delta: -1)),
      const ScoreboardCmd(ClockStartCommand()),
      const ScoreboardCmd(ClockPauseCommand()),
      const ScoreboardCmd(ClockSetCommand(ms: 61000)),
      const ScoreboardCmd(PeriodCommand(delta: 1)),
      ScoreboardCmd(SettingsCommand(ScoreboardState.initial.settings)),
      const ScoreboardCmd(VisibleCommand(visible: false)),
      const ScoreboardCmd(ResetCommand()),
      const BroadcastConfigure(key: 'xxxx-yyyy', targetKbps: 3000, audio: false),
      const BroadcastConfigure(replayScoreboard: true),
      const BroadcastConfigure(),
      const BroadcastStart(),
      const BroadcastStop(),
      const CameraZoom(ratio: 1.5),
      const ClipReserve(size: 3),
      const ReplayAir(clipId: 'c1', speed: 0.5),
      const ReplaySpeed(speed: 0.25),
      const ReplayStop(),
      const MicLevel(db: -18.5),
      const MicLevel(db: null),
      const ClipChanged(
        clip: ClipDto(id: 'c', requestId: 'r', state: ClipState.acked, createdAtMs: 1, reserved: true),
      ),
      const StatusUpdate(
        status: CameraStatus(
          recording: true,
          fps: 30,
          bufferMs: 1,
          outboxClips: 0,
          thermalStatus: 0,
          zoom: ZoomInfo(ratio: 1.5, max: 4),
          reserve: 3,
          replay: ReplayInfo(clipId: 'c1', speed: 0.5, positionMs: 1200, durationMs: 20000),
        ),
      ),
      const Ping(),
      const Pong(),
    ];

    for (final (i, m) in samples.indexed) {
      test('${m.type} round-trips (#$i)', () {
        final back = WsMessage.decode(m.encode());
        expect(back.runtimeType, m.runtimeType);
        expect(back!.toJson(), m.toJson());
      });
    }

    test('unknown types decode to null', () {
      expect(WsMessage.decode('{"type":"future_thing","x":1}'), isNull);
    });

    test('MicLevel: dBFS with one decimal; no db means no microphone', () {
      expect(const MicLevel(db: -23.46).toJson(), {'type': 'mic_level', 'db': -23.5});
      expect(const MicLevel(db: null).toJson(), {'type': 'mic_level'});
      expect((WsMessage.decode('{"type":"mic_level","db":-6}')! as MicLevel).db, -6.0);
      expect((WsMessage.decode('{"type":"mic_level","db":-41.25}')! as MicLevel).db, -41.25);
      expect((WsMessage.decode('{"type":"mic_level"}')! as MicLevel).db, isNull);
      expect((WsMessage.decode(const MicLevel(db: -90).encode())! as MicLevel).db, -90.0);
    });

    test('RecStart: includeSeconds is omitted at 0 and defaults to 0', () {
      expect(const RecStart().toJson(), {'type': 'rec_start'});
      expect(const RecStart(includeSeconds: 30).toJson(), {'type': 'rec_start', 'includeSeconds': 30});
      expect((WsMessage.decode('{"type":"rec_start"}')! as RecStart).includeSeconds, 0);
    });

    test('RecordingFinished carries every field and reason', () {
      for (final reason in RecordingEndReason.values) {
        final m = RecordingFinished(name: 'a.mp4', parts: 1, durationMs: 60000, reason: reason);
        final back = WsMessage.decode(m.encode())! as RecordingFinished;
        expect((back.name, back.parts, back.durationMs, back.reason), ('a.mp4', 1, 60000, reason));
      }
      // A reason this viewer does not know yet reads as a normal save.
      final future = WsMessage.decode(
          '{"type":"recording_finished","name":"a.mp4","parts":1,"durationMs":1,"reason":"cloud"}')! as RecordingFinished;
      expect(future.reason, RecordingEndReason.user);
    });

    test('LiveStart defaults to H264', () {
      expect((WsMessage.decode('{"type":"live_start"}')! as LiveStart).codec, 'H264');
    });
  });

  group('scoreboard', () {
    const s0 = ScoreboardState.initial;

    test('round-trips and fills defaults', () {
      expect(ScoreboardState.fromJson(s0.toJson()), s0);
      final minimal = ScoreboardState.fromJson({
        'home': {'name': 'A', 'color': 1},
        'away': {'name': 'B', 'color': 2},
      });
      expect(minimal.period, 1);
      expect(minimal.clockRunning, isFalse);
      expect(minimal.visible, isTrue);
    });

    test('the scoreboard over replays is off unless the Camera says otherwise', () {
      final info = BroadcastInfo.fromJson({'state': 'idle'});
      expect(info.replayScoreboard, isFalse);
      expect(BroadcastInfo.fromJson({...info.toJson(), 'replayScoreboard': true}).replayScoreboard, isTrue);
      expect(const BroadcastConfigure().toJson().containsKey('replayScoreboard'), isFalse, reason: 'null keeps it');
    });

    test('ClipDto.onCamera: ready, or acked in the reserve', () {
      ClipDto clip(ClipState s, [bool? reserved]) => ClipDto(id: 'c', requestId: 'r', state: s, createdAtMs: 1, reserved: reserved);
      expect(clip(ClipState.ready).onCamera, isTrue);
      expect(clip(ClipState.acked, true).onCamera, isTrue);
      expect(clip(ClipState.acked).onCamera, isFalse);
      expect(clip(ClipState.expired, false).onCamera, isFalse);
      expect(clip(ClipState.recording).onCamera, isFalse);
    });

    test('a status from an older Camera has no scoreboard or broadcast', () {
      final s = CameraStatus.fromJson({'recording': true, 'fps': 30, 'bufferMs': 1, 'outboxClips': 0, 'thermalStatus': 0});
      expect(s.scoreboard, isNull);
      expect(s.broadcast, isNull);
    });

    test('scores never go below zero', () {
      var s = s0.apply(const ScoreCommand(team: Team.home, delta: 1), elapsedMs: 0);
      s = s.apply(const ScoreCommand(team: Team.home, delta: 1), elapsedMs: 0);
      s = s.apply(const ScoreCommand(team: Team.away, delta: -1), elapsedMs: 0);
      expect((s.home.score, s.away.score), (2, 0));
    });

    test('a running clock counts up and is re-anchored by every command', () {
      final running = s0.apply(const ClockStartCommand(), elapsedMs: 0);
      expect(running.clockAt(1500), 1500);
      final scored = running.apply(const ScoreCommand(team: Team.home, delta: 1), elapsedMs: 10000);
      expect(scored.clockMs, 10000);
      expect(scored.clockRunning, isTrue);
      final paused = scored.apply(const ClockPauseCommand(), elapsedMs: 500);
      expect(paused.clockMs, 10500);
      expect(paused.clockAt(99999), 10500);
    });

    test('a count-down clock stops at zero and cannot restart from it', () {
      final s = s0.apply(
        const SettingsCommand(ScoreboardSettings(
          homeName: 'a',
          awayName: 'b',
          homeColor: 1,
          awayColor: 2,
          periods: 4,
          periodMs: 10 * 60 * 1000,
          countDown: true,
        )),
        elapsedMs: 0,
      );
      expect(s.clockMs, 600000);
      final running = s.apply(const ClockStartCommand(), elapsedMs: 0);
      expect(running.clockAt(1000), 599000);
      expect(running.clockAt(700000), 0);
      final ended = running.apply(const ScoreCommand(team: Team.home, delta: 1), elapsedMs: 700000);
      expect((ended.clockMs, ended.clockRunning), (0, false));
      expect(ended.apply(const ClockStartCommand(), elapsedMs: 0).clockRunning, isFalse);
    });

    test('settings normalize names, clamp periods and reset the clock only when it changes', () {
      final running = s0.apply(const ClockStartCommand(), elapsedMs: 0);
      final renamed = running.apply(
        SettingsCommand(ScoreboardSettings(
          homeName: '  barcelona ',
          awayName: '',
          homeColor: 5,
          awayColor: 6,
          periods: 9,
          periodMs: s0.periodMs,
          countDown: false,
        )),
        elapsedMs: 3000,
      );
      // Names are kept whole (up to 16); the classic bar draws only the first 5 letters.
      expect(renamed.home.name, 'BARCELONA');
      expect(ScoreboardState.displayName(renamed.home.name, ScoreboardStyle.classic), 'BARCE');
      expect(ScoreboardState.displayName(renamed.home.name, ScoreboardStyle.plate), 'BARCELONA');
      expect(renamed.style, ScoreboardStyle.classic);
      expect(renamed.away.name, 'VIS');
      expect(ScoreboardState.normalizeName('a' * 30, 'X').length, ScoreboardState.maxNameLength);
      final plate = renamed.apply(
        SettingsCommand(ScoreboardSettings(
          homeName: 'barcelona',
          awayName: 'vis',
          homeColor: 5,
          awayColor: 6,
          periods: 2,
          periodMs: s0.periodMs,
          countDown: false,
          style: ScoreboardStyle.plate,
        )),
        elapsedMs: 0,
      );
      expect(plate.style, ScoreboardStyle.plate);
      expect(ScoreboardState.fromJson(plate.toJson()).style, ScoreboardStyle.plate);
      expect(ScoreboardState.fromJson(s0.toJson()..remove('style')).style, ScoreboardStyle.classic);
      expect(renamed.periods, 4);
      expect((renamed.clockMs, renamed.clockRunning), (3000, true));
    });

    test('period changes pause and reset the clock; reset keeps teams', () {
      final s = s0
          .apply(const ClockStartCommand(), elapsedMs: 0)
          .apply(const ScoreCommand(team: Team.away, delta: 1), elapsedMs: 0)
          .apply(const PeriodCommand(delta: 1), elapsedMs: 2700000);
      expect((s.period, s.clockMs, s.clockRunning), (2, 0, false));
      expect(s.apply(const PeriodCommand(delta: 1), elapsedMs: 0).period, 2);
      final reset = s.apply(const ResetCommand(), elapsedMs: 0);
      expect((reset.period, reset.away.score, reset.away.name), (1, 0, 'VIS'));
    });

    test('scale: defaults to medium, settings change it, old JSON reads as default', () {
      expect(s0.scale, ScoreboardState.defaultScale);
      final json = s0.toJson()..remove('scale');
      expect(ScoreboardState.fromJson(json).scale, ScoreboardState.defaultScale);
      final big = s0.apply(SettingsCommand(ScoreboardSettings(
        homeName: 'A',
        awayName: 'B',
        homeColor: 1,
        awayColor: 2,
        periods: 2,
        periodMs: s0.periodMs,
        countDown: false,
        scale: 160,
      )), elapsedMs: 0);
      expect(big.scale, 160);
      expect(ScoreboardState.fromJson(big.toJson()), big);
    });

    test('formatClock', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(61999), '01:01');
      expect(formatClock(93 * 60000 + 12000), '93:12');
    });

    test('unknown or malformed commands decode to null', () {
      expect(WsMessage.decode('{"type":"scoreboard_cmd","action":"explode"}'), isNull);
      expect(WsMessage.decode('{"type":"scoreboard_cmd","action":"score","team":"nobody","delta":1}'), isNull);
    });
  });
}

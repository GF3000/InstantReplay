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
}

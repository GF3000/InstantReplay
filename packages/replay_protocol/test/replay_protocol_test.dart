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
      const Ping(),
      const Pong(),
    ];

    for (final m in samples) {
      test('${m.type} round-trips', () {
        final back = WsMessage.decode(m.encode());
        expect(back.runtimeType, m.runtimeType);
        expect(back!.toJson(), m.toJson());
      });
    }

    test('unknown types decode to null', () {
      expect(WsMessage.decode('{"type":"future_thing","x":1}'), isNull);
    });

    test('LiveStart defaults to H264', () {
      expect((WsMessage.decode('{"type":"live_start"}')! as LiveStart).codec, 'H264');
    });
  });
}

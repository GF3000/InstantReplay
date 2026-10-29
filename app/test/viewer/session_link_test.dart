import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/data/viewer_api.dart';
import 'package:replay_protocol/replay_protocol.dart';

import 'fakes.dart';

const camera = CameraInfo(protocolVersion: protocolVersion, cameraId: 'cam1', name: 'Pitch', profileId: '1080p30');

void main() {
  late List<FakeChannel> channels;
  late List<Uri> connectedTo;
  var infoStatus = 200;

  SessionLink link() {
    channels = [];
    connectedTo = [];
    final api = ViewerApi(
      client: MockClient((r) async => http.Response(jsonEncode(camera.toJson()), infoStatus)),
      base: Uri.parse('http://cam:8080'),
      token: 'tok',
    );
    final l = SessionLink(
      api: api,
      viewerId: 'me',
      connect: (uri) async {
        connectedTo.add(uri);
        final ch = FakeChannel();
        channels.add(ch);
        return ch;
      },
      pingInterval: const Duration(milliseconds: 20),
      silenceTimeout: const Duration(seconds: 5),
      backoff: const [Duration(milliseconds: 10)],
    );
    addTearDown(l.dispose);
    return l;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  setUp(() => infoStatus = 200);

  test('hello → welcome → connected; pings; status updates; reconnects after a drop', () async {
    final l = link()..start();
    await until(() => channels.isNotEmpty && channels.first.sent.isNotEmpty);
    expect(connectedTo.single.toString(), 'ws://cam:8080${Api.ws}?k=tok');
    final hello = WsMessage.decode(channels.first.sent.first)! as Hello;
    expect((hello.viewerId, hello.protocolVersion), ('me', protocolVersion));
    expect(l.state.phase, LinkPhase.connecting);

    channels.first.push(const Welcome(camera: camera).encode());
    await until(() => l.isConnected);
    expect(l.state.camera?.name, 'Pitch');

    const status = CameraStatus(recording: true, fps: 30, bufferMs: 60000, outboxClips: 1, thermalStatus: 0);
    channels.first.push(const StatusUpdate(status: status).encode());
    await until(() => l.state.status != null);

    await until(() => channels.first.sent.any((s) => WsMessage.decode(s) is Ping));
    expect(l.send(const LiveStart()), isTrue);

    await channels.first.drop();
    await until(() => channels.length == 2);
    expect(l.state.phase, LinkPhase.reconnecting);
    expect(l.send(const LiveStart()), isFalse);
    channels.last.push(const Welcome(camera: camera).encode());
    await until(() => l.isConnected);
  });

  test('a rejected token stops the link as unauthorized', () async {
    infoStatus = 401;
    final l = link()..start();
    await until(() => l.state.phase == LinkPhase.unauthorized);
    expect(channels, isEmpty);
  });

  test('another protocol version stops the link as incompatible', () async {
    final l = link()..start();
    await until(() => channels.isNotEmpty);
    channels.first.push(const Welcome(
      camera: CameraInfo(protocolVersion: protocolVersion + 1, cameraId: 'c', name: 'Future'),
    ).encode());
    await until(() => l.state.phase == LinkPhase.incompatible);
  });
}

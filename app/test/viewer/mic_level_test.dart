import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/data/viewer_api.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:replay_protocol/replay_protocol.dart';

import 'fakes.dart';

const _camera = CameraInfo(protocolVersion: protocolVersion, cameraId: 'cam1', name: 'Pitch', profileId: '1080p30');

void main() {
  test('the mic level follows mic_level messages, clears on null and when they stop', () async {
    final channels = <FakeChannel>[];
    final link = SessionLink(
      api: ViewerApi(
        client: MockClient((r) async => http.Response(jsonEncode(_camera.toJson()), 200)),
        base: Uri.parse('http://cam:8080'),
        token: 'tok',
      ),
      viewerId: 'me',
      connect: (uri) async {
        final ch = FakeChannel();
        channels.add(ch);
        return ch;
      },
    );
    addTearDown(link.dispose);
    link.start();
    final container = ProviderContainer(overrides: [sessionLinkProvider.overrideWithValue(link)]);
    addTearDown(container.dispose);
    final sub = container.listen(viewerMicLevelProvider, (_, _) {});
    addTearDown(sub.close);

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(condition(), isTrue);
    }

    expect(sub.read(), isNull);
    await until(() => channels.isNotEmpty);
    channels.first.push(const Welcome(camera: _camera).encode());
    await until(() => link.isConnected);

    channels.first.push(const MicLevel(db: -20).encode());
    await until(() => sub.read() == -20);
    channels.first.push(const MicLevel(db: null).encode());
    await until(() => sub.read() == null);

    // A Camera that stops sending (or a lost link): the meter goes away after a second.
    channels.first.push(const MicLevel(db: -30).encode());
    await until(() => sub.read() == -30);
    await Future<void>.delayed(ViewerMicLevelNotifier.stale + const Duration(milliseconds: 100));
    expect(sub.read(), isNull);
  });
}

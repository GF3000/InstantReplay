import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/broadcast/broadcast_controller.dart';
import 'package:instant_replay/features/broadcast/broadcast_host.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show BroadcastState, BroadcastStatus;
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera/fake_capture_layer.dart';

void main() {
  late SharedPreferences prefs;
  late FakeCaptureLayer capture;

  BroadcastController controller() => BroadcastController(prefs: prefs, capture: capture);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    capture = FakeCaptureLayer();
  });

  test('stream url joins server and key with one slash', () {
    expect(BroadcastController.streamUrl('rtmp://a.rtmp.youtube.com/live2', 'abcd-1234'),
        'rtmp://a.rtmp.youtube.com/live2/abcd-1234');
    expect(BroadcastController.streamUrl(' rtmps://x/live2// ', ' k '), 'rtmps://x/live2/k');
  });

  test('key hint is the last 4 characters', () {
    expect(BroadcastController.keyHint('abcd-efgh-ijkl'), 'ijkl');
    expect(BroadcastController.keyHint(null), isNull);
    expect(BroadcastController.keyHint(''), isNull);
  });

  test('bitrate is clamped to 2500–6000', () {
    expect(BroadcastController.clampKbps(1000), 2500);
    expect(BroadcastController.clampKbps(4500), 4500);
    expect(BroadcastController.clampKbps(9000), 6000);
  });

  test('defaults: YouTube server, 4500 kbps, audio on, not configured', () {
    final info = controller().info;
    expect(info.server, BroadcastInfo.defaultServer);
    expect(info.targetKbps, 4500);
    expect(info.audio, isTrue);
    expect(info.configured, isFalse);
    expect(info.keyHint, isNull);
    expect(info.state, BroadcastStreamState.idle);
  });

  test('start without a key is not_configured', () async {
    await expectLater(
        controller().start(), throwsA(isA<BroadcastException>().having((e) => e.code, 'code', 'not_configured')));
    expect(capture.calls, isNot(contains('broadcastStart')));
  });

  test('configure stores the settings; the key never shows, only its hint', () async {
    final c = controller();
    await c.configure(server: 'rtmp://x/live2/', key: '  secret-key-WXYZ ', targetKbps: 9000, audio: false);
    final info = c.info;
    expect(info.configured, isTrue);
    expect(info.server, 'rtmp://x/live2/');
    expect(info.keyHint, 'WXYZ');
    expect(info.targetKbps, 6000);
    expect(info.audio, isFalse);
    expect(jsonEncode(info.toJson()), isNot(contains('secret')));

    // An empty or null key keeps the stored one; survives a restart.
    await c.configure(server: '', key: '', targetKbps: 3000, audio: true);
    final again = controller().info;
    expect(again.keyHint, 'WXYZ');
    expect(again.server, BroadcastInfo.defaultServer);
    expect(again.targetKbps, 3000);
  });

  test('start asks for the microphone and sends url, bitrate and audio', () async {
    final c = controller();
    await c.configure(server: 'rtmp://a.rtmp.youtube.com/live2/', key: 'abcd', targetKbps: 5000, audio: true);
    final changed = c.stateChanges.first;
    expect(await c.start(), isTrue);
    await changed;
    expect(capture.calls, containsAllInOrder(['micPermission', 'broadcastStart']));
    final config = capture.broadcastConfigs.single;
    expect(config.url, 'rtmp://a.rtmp.youtube.com/live2/abcd');
    expect(config.targetKbps, 5000);
    expect(config.audio, isTrue);
    expect(c.info.state, BroadcastStreamState.connecting);
  });

  test('a denied microphone streams without audio and says so', () async {
    capture.micGranted = false;
    final c = controller();
    await c.configure(server: BroadcastInfo.defaultServer, key: 'abcd', targetKbps: 4500, audio: true);
    expect(await c.start(), isFalse);
    expect(capture.broadcastConfigs.single.audio, isFalse);
  });

  test('audio off does not ask for the microphone', () async {
    final c = controller();
    await c.configure(server: BroadcastInfo.defaultServer, key: 'abcd', targetKbps: 4500, audio: false);
    expect(await c.start(), isTrue);
    expect(capture.calls, isNot(contains('micPermission')));
  });

  test('a plugin failure is broadcast_failed', () async {
    capture.broadcastStartError = PlatformException(code: 'encoder', message: 'no encoder');
    final c = controller();
    await c.configure(server: BroadcastInfo.defaultServer, key: 'abcd', targetKbps: 4500, audio: false);
    await expectLater(
      c.start(),
      throwsA(isA<BroadcastException>()
          .having((e) => e.code, 'code', 'broadcast_failed')
          .having((e) => e.message, 'message', 'no encoder')),
    );
  });

  test('native state and numbers reach the info', () async {
    final c = controller();
    final next = c.changes.first;
    capture.broadcastController.add(BroadcastStatus(
      state: BroadcastState.live,
      targetKbps: 4000,
      droppedFrames: 0,
      audio: true,
      bitrateKbps: 4100,
      uptimeMs: 65000,
    ));
    final info = await next;
    expect(info.state, BroadcastStreamState.live);
    expect(info.bitrateKbps, 4100);
    expect(info.uptimeMs, 65000);
    expect(info.targetKbps, 4500, reason: 'the configured target, not the adaptive one');

    await c.stop();
    expect(capture.calls.last, 'broadcastStop');
    expect(c.info.state, BroadcastStreamState.idle);
  });
}

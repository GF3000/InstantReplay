import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/server/camera_server.dart';
import 'package:instant_replay/features/server/pairing.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show RecordingEnd, RecordingSaved, RecordingState;
import 'package:replay_protocol/replay_protocol.dart';

import '../camera/fake_capture_layer.dart';

const _token = '0123456789abcdef0123456789abcdef';
const _code = '123456';

typedef _Reply = ({int status, HttpHeaders headers, List<int> body});

/// A WebSocket client that queues decoded messages.
class _Viewer {
  _Viewer._(this.ws) {
    ws.listen((raw) {
      final m = WsMessage.decode(raw as String);
      if (m == null) return;
      final w = _waiters.where((w) => w.$1(m)).firstOrNull;
      if (w != null) {
        _waiters.remove(w);
        w.$2.complete(m);
      } else {
        _queue.add(m);
      }
    });
  }

  static Future<_Viewer> connect(int port, {String token = _token}) async =>
      _Viewer._(await WebSocket.connect('ws://127.0.0.1:$port${Api.ws}?${Api.tokenParam}=$token'));

  final WebSocket ws;
  final _queue = <WsMessage>[];
  final _waiters = <(bool Function(WsMessage), Completer<WsMessage>)>[];

  void send(WsMessage m) => ws.add(m.encode());

  /// The next message of type [T], skipping others.
  Future<T> next<T extends WsMessage>() {
    final queued = _queue.whereType<T>().firstOrNull;
    if (queued != null) {
      _queue.remove(queued);
      return Future.value(queued);
    }
    final c = Completer<WsMessage>();
    _waiters.add(((m) => m is T, c));
    return c.future.timeout(const Duration(seconds: 3)).then((m) => m as T);
  }

  List<WsMessage> get received => List.unmodifiable(_queue);

  Future<Welcome> hello(String viewerId) {
    send(Hello(protocolVersion: protocolVersion, viewerId: viewerId));
    return next<Welcome>();
  }

  Future<void> close() => ws.close();
}

void main() {
  late FakeCaptureLayer capture;
  late CameraServer server;
  late int port;
  late DateTime clock;
  late Directory temp;
  final client = HttpClient();

  Future<void> startServer({String? webRoot, Duration silence = const Duration(seconds: 15)}) async {
    server = CameraServer(
      capture: capture,
      secrets: PairingSecrets(code: _code, token: _token),
      cameraInfo: () => const CameraInfo(protocolVersion: 1, cameraId: 'cam-1', name: 'Test Phone', profileId: '1080p30'),
      webRoot: webRoot,
      silenceTimeout: silence,
      pairLimiter: AttemptLimiter(now: () => clock),
    );
    port = await server.start(address: InternetAddress.loopbackIPv4, port: 0);
  }

  Future<_Reply> call(String method, String path,
      {Object? json, bool auth = true, Map<String, String> headers = const {}}) async {
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (auth) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    headers.forEach(req.headers.set);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    final res = await req.close();
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    return (status: res.statusCode, headers: res.headers, body: body);
  }

  Object? decode(_Reply r) => jsonDecode(utf8.decode(r.body));

  setUp(() async {
    capture = FakeCaptureLayer()..autoFinishClips = false;
    clock = DateTime(2026, 10, 29, 12);
    temp = await Directory.systemTemp.createTemp('camera_server_test');
  });

  tearDown(() async {
    await server.close();
    await temp.delete(recursive: true);
  });

  group('pairing', () {
    setUp(startServer);

    test('the right code returns the token', () async {
      final r = await call('POST', Api.pair, json: const PairRequest(code: _code).toJson(), auth: false);
      expect(r.status, 200);
      expect(PairResponse.fromJson(decode(r)! as Json).token, _token);
    });

    test('a wrong code is refused', () async {
      final r = await call('POST', Api.pair, json: const PairRequest(code: '000000').toJson(), auth: false);
      expect(r.status, 403);
      expect((decode(r)! as Json)['code'], 'wrong_code');
    });

    test('more than 5 attempts a minute are rate-limited', () async {
      for (var i = 0; i < 5; i++) {
        expect((await call('POST', Api.pair, json: {'code': '00000$i'}, auth: false)).status, 403);
      }
      final limited = await call('POST', Api.pair, json: {'code': _code}, auth: false);
      expect(limited.status, 429);
      expect(limited.headers.value(HttpHeaders.retryAfterHeader), '60');

      clock = clock.add(const Duration(seconds: 61));
      expect((await call('POST', Api.pair, json: {'code': _code}, auth: false)).status, 200);
    });

    test('a malformed body is a 400', () async {
      expect((await call('POST', Api.pair, json: {'nope': 1}, auth: false)).status, 400);
    });
  });

  group('auth', () {
    setUp(startServer);

    test('API routes need the token', () async {
      expect((await call('GET', Api.info, auth: false)).status, 401);
      expect((await call('GET', Api.clips, auth: false)).status, 401);
      expect((await call('GET', Api.info, auth: false, headers: {'authorization': 'Bearer wrong'})).status, 401);
      expect((await call('GET', '${Api.info}?${Api.tokenParam}=wrong', auth: false)).status, 401);
    });

    test('bearer header or ?k= are accepted', () async {
      final r = await call('GET', Api.info);
      expect(r.status, 200);
      final info = CameraInfo.fromJson(decode(r)! as Json);
      expect(info.cameraId, 'cam-1');
      expect(info.protocolVersion, protocolVersion);
      expect(info.profileId, '1080p30');
      expect((await call('GET', '${Api.info}?${Api.tokenParam}=$_token', auth: false)).status, 200);
    });

    test('the WebSocket needs the token', () async {
      await expectLater(_Viewer.connect(port, token: 'wrong'), throwsA(isA<WebSocketException>()));
    });

    test('the web page does not need the token', () async {
      final r = await call('GET', '/', auth: false);
      expect(r.status, 200);
      expect(utf8.decode(r.body), contains('not bundled'));
    });
  });

  group('clips', () {
    setUp(startServer);

    test('save answers 202 recording without waiting for the clip', () async {
      final r = await call('POST', Api.clips,
          json: const SaveClipRequest(requestId: 'r1', preSeconds: 20, viewerId: 'viewer-a').toJson());
      expect(r.status, 202);
      final clip = ClipDto.fromJson(decode(r)! as Json);
      expect(clip.state, ClipState.recording);
      expect(clip.requestId, 'r1');
      expect(clip.requestedBy, 'viewer-a');
    });

    test('a repeated requestId never cuts twice', () async {
      const body = SaveClipRequest(requestId: 'r1', preSeconds: 20, viewerId: 'viewer-a');
      final replies = await Future.wait([
        call('POST', Api.clips, json: body.toJson()),
        call('POST', Api.clips, json: body.toJson()),
      ]);
      final again = await call('POST', Api.clips, json: body.toJson());
      final ids = {for (final r in [...replies, again]) ClipDto.fromJson(decode(r)! as Json).id};
      expect(ids, hasLength(1));
      expect(capture.calls.where((c) => c.startsWith('save:')), hasLength(1));
    });

    test('invalid save requests are 400', () async {
      expect((await call('POST', Api.clips, json: {'requestId': 'r', 'preSeconds': 0})).status, 400);
      expect((await call('POST', Api.clips, json: {'preSeconds': 10})).status, 400);
    });

    test('GET clips lists the outbox with requestedBy', () async {
      await call('POST', Api.clips, json: const SaveClipRequest(requestId: 'r1', preSeconds: 10, viewerId: 'v').toJson());
      final r = await call('GET', Api.clips);
      final list = [for (final j in decode(r)! as List) ClipDto.fromJson(j as Json)];
      expect(list.single.requestedBy, 'v');
      expect(list.single.state, ClipState.recording);
    });

    test('download supports Range and is 404 until ready', () async {
      final r = await call('POST', Api.clips, json: const SaveClipRequest(requestId: 'r1', preSeconds: 10).toJson());
      final id = ClipDto.fromJson(decode(r)! as Json).id;
      expect((await call('GET', Api.clip(id))).status, 404);
      expect((await call('GET', Api.clip('nope'))).status, 404);

      final bytes = List.generate(1000, (i) => i % 256);
      final file = File('${temp.path}/clip.mp4')..writeAsBytesSync(bytes);
      capture.finishClip(id, path: file.path, bytes: bytes.length);

      final full = await call('GET', Api.clip(id));
      expect(full.status, 200);
      expect(full.body, bytes);
      expect(full.headers.contentType?.mimeType, 'video/mp4');
      expect(full.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');

      final part = await call('GET', Api.clip(id), headers: {'range': 'bytes=100-199'});
      expect(part.status, 206);
      expect(part.body, bytes.sublist(100, 200));
      expect(part.headers.value(HttpHeaders.contentRangeHeader), 'bytes 100-199/1000');

      final open = await call('GET', Api.clip(id), headers: {'range': 'bytes=990-'});
      expect(open.body, bytes.sublist(990));

      final suffix = await call('GET', Api.clip(id), headers: {'range': 'bytes=-10'});
      expect(suffix.status, 206);
      expect(suffix.body, bytes.sublist(990));

      final bad = await call('GET', Api.clip(id), headers: {'range': 'bytes=5000-'});
      expect(bad.status, 416);
      expect(bad.headers.value(HttpHeaders.contentRangeHeader), 'bytes */1000');

      // The browser <video> path: token in the query.
      final query = await call('GET', '${Api.clip(id)}?${Api.tokenParam}=$_token', auth: false);
      expect(query.status, 200);
    });

    test('ack is 204 with the right hash and 409 otherwise', () async {
      final r = await call('POST', Api.clips, json: const SaveClipRequest(requestId: 'r1', preSeconds: 10).toJson());
      final id = ClipDto.fromJson(decode(r)! as Json).id;
      capture.finishClip(id);

      expect((await call('POST', Api.ack(id), json: const AckRequest(sha256: 'bad').toJson())).status, 409);
      expect((await call('POST', Api.ack(id), json: AckRequest(sha256: capture.acceptedSha256).toJson())).status, 204);
      expect((await call('POST', Api.ack('nope'), json: const AckRequest(sha256: 'x').toJson())).status, 404);
    });
  });

  group('WebSocket', () {
    setUp(startServer);

    test('hello → welcome; nothing else before hello; ping → pong', () async {
      final v = await _Viewer.connect(port);
      v.send(const LiveStart());
      expect((await v.next<ErrorMessage>()).code, 'hello_required');
      expect(capture.calls.where((c) => c.startsWith('liveOffer')), isEmpty);

      final welcome = await v.hello('viewer-a');
      expect(welcome.camera.cameraId, 'cam-1');
      expect(welcome.camera.name, 'Test Phone');

      v.send(const Ping());
      await v.next<Pong>();
      await v.close();
    });

    test('a different protocol version is refused', () async {
      final v = await _Viewer.connect(port);
      v.send(const Hello(protocolVersion: 99, viewerId: 'x'));
      expect((await v.next<ErrorMessage>()).code, 'unsupported_protocol');
      await v.ws.done.timeout(const Duration(seconds: 3));
    });

    test('signaling: offer first, then trickled candidates both ways, and close on stop', () async {
      final v = await _Viewer.connect(port);
      await v.hello('viewer-a');
      // A candidate that overtakes the offer must be held until the offer is sent.
      capture.onLiveOffer = (id) =>
          capture.liveIceController.add((viewerId: id, candidate: 'early', sdpMid: '0', sdpMLineIndex: 0));

      v.send(const LiveStart(codec: 'VP8'));
      final offer = await v.next<RtcOffer>();
      expect(offer.sdp, 'offer-sdp-viewer-a');
      expect(capture.calls, contains('liveOffer:viewer-a:VP8'));
      final early = await v.next<RtcIce>();
      expect((early.candidate, early.sdpMid, early.sdpMLineIndex), ('early', '0', 0));

      capture.liveIceController
        ..add((viewerId: 'someone-else', candidate: 'other', sdpMid: null, sdpMLineIndex: null))
        ..add((viewerId: 'viewer-a', candidate: 'late', sdpMid: '0', sdpMLineIndex: 0));
      expect((await v.next<RtcIce>()).candidate, 'late');

      v
        ..send(const RtcAnswer(sdp: 'answer-sdp'))
        ..send(const RtcIce(candidate: 'remote', sdpMid: '0', sdpMLineIndex: 0))
        ..send(const LiveStop())
        ..send(const Ping());
      await v.next<Pong>();
      await pumpEventQueue();
      expect(
        capture.calls.where((c) => c.startsWith('live')),
        containsAllInOrder([
          'liveAnswer:viewer-a:answer-sdp',
          'liveIce:viewer-a:remote:0:0',
          'liveClose:viewer-a',
        ]),
      );
      expect(v.received.whereType<RtcIce>().where((m) => m.candidate == 'other'), isEmpty);
      await v.close();
    });

    test('closing the socket closes the live session', () async {
      final v = await _Viewer.connect(port);
      await v.hello('viewer-a');
      v.send(const LiveStart());
      await v.next<RtcOffer>();
      await v.close();
      await _eventually(() => capture.calls.contains('liveClose:viewer-a'));
    });

    test('clip changes are broadcast with requestedBy', () async {
      final a = await _Viewer.connect(port);
      final b = await _Viewer.connect(port);
      await a.hello('viewer-a');
      await b.hello('viewer-b');

      final r = await call('POST', Api.clips,
          json: const SaveClipRequest(requestId: 'r1', preSeconds: 10, viewerId: 'viewer-a').toJson());
      final id = ClipDto.fromJson(decode(r)! as Json).id;
      for (final v in [a, b]) {
        final changed = (await v.next<ClipChanged>()).clip;
        expect((changed.id, changed.state, changed.requestedBy), (id, ClipState.recording, 'viewer-a'));
      }

      capture.finishClip(id, bytes: 1234);
      for (final v in [a, b]) {
        final ready = (await v.next<ClipChanged>()).clip;
        expect((ready.state, ready.bytes, ready.sha256, ready.requestedBy),
            (ClipState.ready, 1234, capture.acceptedSha256, 'viewer-a'));
      }
      await a.close();
      await b.close();
    });

    test('stats become status updates', () async {
      final v = await _Viewer.connect(port);
      await v.hello('viewer-a');
      capture.statsController.add(stats(bufferMs: 30000, outboxClips: 2));
      final status = (await v.next<StatusUpdate>()).status;
      expect((status.recording, status.bufferMs, status.outboxClips, status.fps), (true, 30000, 2, 30.0));
      await v.close();
    });

    test('the viewer count follows hello and close', () async {
      final counts = <int>[];
      server.viewerCountChanges.listen(counts.add);
      final v = await _Viewer.connect(port);
      await v.hello('viewer-a');
      expect(server.viewerCount, 1);
      await v.close();
      await _eventually(() => server.viewerCount == 0);
      expect(counts, [1, 0]);
    });
  });

  group('full-session recording', () {
    setUp(startServer);

    Future<_Viewer> greeted(String id) async {
      final v = await _Viewer.connect(port);
      await v.hello(id);
      return v;
    }

    test('stats carry the recording into the status', () async {
      final v = await greeted('viewer-a');
      capture.statsController.add(stats(recording: recStatus(state: RecordingState.recording, elapsedMs: 61000, parts: 2)));
      final r = (await v.next<StatusUpdate>()).status.sessionRecording!;
      expect((r.state, r.elapsedMs, r.parts, r.lowSpace), (SessionRecordingState.recording, 61000, 2, false));
      await v.close();
    });

    test('rec_start, rec_pause and rec_stop drive the recorder and every viewer hears at once', () async {
      final a = await greeted('viewer-a');
      final b = await greeted('viewer-b');
      capture.statsController.add(stats(recording: recStatus()));
      for (final v in [a, b]) {
        expect((await v.next<StatusUpdate>()).status.sessionRecording!.state, SessionRecordingState.idle);
      }

      // Well inside the 1 s stats throttle: the update must not wait for the next tick.
      a.send(const RecStart(includeSeconds: 30));
      for (final v in [a, b]) {
        expect((await v.next<StatusUpdate>()).status.sessionRecording!.state, SessionRecordingState.recording);
      }
      expect(capture.calls, contains('recordStart:30'));

      b.send(const RecPause());
      for (final v in [a, b]) {
        final s = (await v.next<StatusUpdate>()).status;
        expect(s.sessionRecording!.state, SessionRecordingState.paused);
        // The rest of the status is the last one from the stats.
        expect((s.bufferMs, s.outboxClips), (42000, 3));
      }

      a.send(const RecStop());
      for (final v in [a, b]) {
        final finished = await v.next<RecordingFinished>();
        expect((finished.name, finished.reason), ('InstantReplay_2026-10-30_11-30.mp4', RecordingEndReason.user));
        expect((await v.next<StatusUpdate>()).status.sessionRecording!.state, SessionRecordingState.idle);
      }
      expect(capture.calls.where((c) => c.startsWith('record')), ['recordStart:30', 'recordPause', 'recordStop']);
      // A command's result and the recorder's event are one change: sent once.
      expect(a.received.whereType<StatusUpdate>(), isEmpty);
      await a.close();
      await b.close();
    });

    test('a recording event before any stats waits for the first tick', () async {
      final v = await greeted('viewer-a');
      capture.recordingController.add(recStatus(state: RecordingState.recording, elapsedMs: 5000));
      capture.statsController.add(stats());
      expect((await v.next<StatusUpdate>()).status.sessionRecording!.elapsedMs, 5000);
      await v.close();
    });

    test('a stop by the Camera for low space reaches every viewer', () async {
      final a = await greeted('viewer-a');
      final b = await greeted('viewer-b');
      capture.recordingSavedController.add(RecordingSaved(
        name: 'InstantReplay_2026-10-30_11-30.mp4',
        parts: 3,
        durationMs: 2820000,
        bytes: 1,
        reason: RecordingEnd.lowSpace,
      ));
      for (final v in [a, b]) {
        final m = await v.next<RecordingFinished>();
        expect((m.parts, m.durationMs, m.reason), (3, 2820000, RecordingEndReason.lowSpace));
      }
      await a.close();
      await b.close();
    });

    test('no space and other failures come back as error codes', () async {
      final v = await greeted('viewer-a');
      capture.recordStartError = PlatformException(code: 'no_space', message: 'Less than 1 GB free');
      v.send(const RecStart());
      final noSpace = await v.next<ErrorMessage>();
      expect((noSpace.code, noSpace.message), ('no_space', 'Less than 1 GB free'));

      capture.recordStartError = Exception('muxer broke');
      v.send(const RecStart());
      expect((await v.next<ErrorMessage>()).code, 'rec_failed');
      await v.close();
    });

    test('the recording carries on when a viewer leaves', () async {
      final a = await greeted('viewer-a');
      a.send(const RecStart());
      await _eventually(() => capture.calls.contains('recordStart:0'));
      await a.close();
      await _eventually(() => server.viewerCount == 0);
      expect(capture.calls.where((c) => c == 'recordStop' || c == 'recordPause'), isEmpty);
      expect(capture.recordingState.state, RecordingState.recording);
    });

    test('rec_* need hello first', () async {
      final v = await _Viewer.connect(port);
      v.send(const RecStart());
      expect((await v.next<ErrorMessage>()).code, 'hello_required');
      expect(capture.calls.where((c) => c.startsWith('record')), isEmpty);
      await v.close();
    });
  });

  test('silent viewers are dropped', () async {
    await startServer(silence: const Duration(milliseconds: 300));
    final v = await _Viewer.connect(port);
    await v.hello('viewer-a');
    v.send(const LiveStart());
    await v.next<RtcOffer>();
    await v.ws.done.timeout(const Duration(seconds: 3));
    await _eventually(() => capture.calls.contains('liveClose:viewer-a'));
    expect(server.viewerCount, 0);
  });

  test('serves the web bundle with SPA fallback', () async {
    File('${temp.path}/index.html').writeAsStringSync('<html>viewer</html>');
    File('${temp.path}/main.dart.js').writeAsStringSync('console.log(1)');
    await startServer(webRoot: temp.path);

    expect(utf8.decode((await call('GET', '/?k=$_token', auth: false)).body), '<html>viewer</html>');
    expect(utf8.decode((await call('GET', '/main.dart.js', auth: false)).body), 'console.log(1)');
    final route = await call('GET', '/review/42', auth: false);
    expect(route.status, 200);
    expect(utf8.decode(route.body), '<html>viewer</html>');
    expect((await call('GET', '${Api.prefix}/unknown')).status, 404);
  });
}

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

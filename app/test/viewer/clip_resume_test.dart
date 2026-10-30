import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:instant_replay/features/server/camera_server.dart';
import 'package:instant_replay/features/server/pairing.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/clips/partial_download_io.dart';
import 'package:instant_replay/features/viewer/data/viewer_api.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../camera/fake_capture_layer.dart';
import 'fakes.dart';

const _token = '0123456789abcdef0123456789abcdef';

/// A TCP proxy in front of the Camera that drops the connection in the middle of clip downloads,
/// like a Wi-Fi drop: the next [cuts] download responses are cut after [cutAfter] bytes.
class CuttingProxy {
  CuttingProxy._(this._server, this._upstreamPort) {
    _server.listen(_relay);
  }

  static Future<CuttingProxy> start(int upstreamPort) async =>
      CuttingProxy._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), upstreamPort);

  final ServerSocket _server;
  final int _upstreamPort;
  int cuts = 0;
  int cutAfter = 0;

  /// The head of each download request.
  final downloads = <String>[];

  int get port => _server.port;

  Future<void> _relay(Socket client) async {
    final upstream = await Socket.connect(InternetAddress.loopbackIPv4, _upstreamPort);
    var cutting = false;
    var relayed = 0;
    client.listen(
      (data) {
        final head = latin1.decode(data);
        if (head.startsWith('GET ${Api.clips}/')) {
          downloads.add(head);
          cutting = cuts > 0;
          relayed = 0;
        }
        upstream.add(data);
      },
      onDone: upstream.destroy,
      onError: (_) => upstream.destroy(),
    );
    upstream.listen(
      (data) {
        if (cutting && relayed + data.length > cutAfter) {
          cuts--;
          cutting = false;
          client.add(data.sublist(0, cutAfter - relayed));
          unawaited(client.flush().whenComplete(client.destroy));
          upstream.destroy();
          return;
        }
        relayed += data.length;
        client.add(data);
      },
      onDone: client.destroy,
      onError: (_) => client.destroy(),
    );
  }

  Future<void> close() => _server.close();
}

void main() {
  late Directory temp;
  late FakeCaptureLayer capture;
  late CameraServer server;
  late CuttingProxy proxy;
  late MemoryClipStore store;
  late ClipTransfers transfers;
  final file = Uint8List.fromList(List.generate(3 * 1024 * 1024, (i) => (i * 31 + (i >> 11)) % 256));
  final sha = sha256.convert(file).toString();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('clip_resume_test');
    capture = FakeCaptureLayer()
      ..autoFinishClips = false
      ..acceptedSha256 = sha;
    server = CameraServer(
      capture: capture,
      secrets: PairingSecrets(code: '123456', token: _token),
      cameraInfo: () => const CameraInfo(protocolVersion: 1, cameraId: 'cam-1', name: 'Test', profileId: '1080p30'),
    );
    proxy = await CuttingProxy.start(await server.start(address: InternetAddress.loopbackIPv4, port: 0));
    store = MemoryClipStore();
    transfers = ClipTransfers(
      store: store,
      viewerId: 'viewer-me',
      onChanged: (_) {},
      newPartial: (id) => FilePartialDownload(() async => File('${temp.path}/$id.part')),
      retryDelay: const Duration(milliseconds: 20),
    )..api = ViewerApi(client: IOClient(), base: Uri.parse('http://127.0.0.1:${proxy.port}'), token: _token);
  });

  tearDown(() async {
    await transfers.dispose();
    await proxy.close();
    await server.close();
    await temp.delete(recursive: true);
  });

  Future<SessionClip> saveAndFinish() async {
    await transfers.save(seconds: 10);
    final id = capture.outbox.keys.single;
    final path = '${temp.path}/$id.mp4';
    await File(path).writeAsBytes(file);
    capture.finishClip(id, path: path, bytes: file.length, sha256: sha);
    unawaited(transfers.recover()); // As on reconnect: GET /clips finds it ready.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final c = transfers.clips.single;
      if (c.acked || c.phase == SessionClipPhase.failed) return c;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('the clip did not finish');
  }

  int rangeStart(String head) =>
      int.parse(RegExp(r'^range: bytes=(\d+)-\r?$', caseSensitive: false, multiLine: true).firstMatch(head)![1]!);

  test('the connection drops twice mid-transfer; the clip still arrives with the right hash', () async {
    proxy
      ..cuts = 2
      ..cutAfter = 1024 * 1024;

    final c = await saveAndFinish();

    expect(c.phase, SessionClipPhase.ready);
    expect(c.acked, isTrue);
    expect(sha256.convert(store.stored[c.clipId]!).toString(), sha);
    expect(capture.calls, contains('ack:${c.clipId}:$sha'));
    expect(proxy.downloads, hasLength(3));
    expect(proxy.downloads.first, isNot(contains(RegExp('^range:', caseSensitive: false, multiLine: true))));
    final first = rangeStart(proxy.downloads[1]), second = rangeStart(proxy.downloads[2]);
    expect(first, greaterThan(0));
    expect(second, greaterThan(first));
    expect(temp.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });

  test('without cuts the clip downloads in one request', () async {
    final c = await saveAndFinish();
    expect(c.acked, isTrue);
    expect(proxy.downloads, hasLength(1));
    expect(store.stored[c.clipId], file);
  });
}

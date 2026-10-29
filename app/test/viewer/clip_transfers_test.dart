import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/clips/save_presets.dart';
import 'package:instant_replay/features/viewer/data/viewer_api.dart';
import 'package:replay_protocol/replay_protocol.dart';

import 'fakes.dart';

const me = 'viewer-me';

/// Plays the Camera's REST side.
class FakeCamera {
  final file = Uint8List.fromList(List.generate(100000, (i) => i * 7 % 256));
  final saves = <SaveClipRequest>[];
  final acks = <String, String>{};
  int downloads = 0;
  int failSaves = 0;
  int corruptDownloads = 0;
  Completer<void>? saveGate;
  Completer<void>? downloadGate;

  String get sha => sha256.convert(file).toString();

  ClipDto dto(String requestId, ClipState state, {String requestedBy = me}) => ClipDto(
        id: 'clip-$requestId',
        requestId: requestId,
        state: state,
        createdAtMs: 1000,
        requestedBy: requestedBy,
        bytes: state == ClipState.ready ? file.length : null,
        durationMs: state == ClipState.ready ? 22000 : null,
        sha256: state == ClipState.ready ? sha : null,
      );

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    if (r.method == 'POST' && path == Api.clips) {
      final req = SaveClipRequest.fromJson(jsonDecode(r.body) as Json);
      saves.add(req);
      await saveGate?.future;
      if (failSaves > 0) {
        failSaves--;
        return http.Response('busy', 503);
      }
      return http.Response(jsonEncode(dto(req.requestId, ClipState.recording, requestedBy: req.viewerId!).toJson()), 202);
    }
    if (r.method == 'GET' && path.startsWith('${Api.clips}/')) {
      downloads++;
      await downloadGate?.future;
      if (corruptDownloads > 0) {
        corruptDownloads--;
        return http.Response.bytes(Uint8List.fromList([...file]..[0] ^= 0xff), 200);
      }
      return http.Response.bytes(file, 200, headers: {'content-length': '${file.length}'});
    }
    if (r.method == 'POST' && path.endsWith('/ack')) {
      final id = path.split('/')[path.split('/').length - 2];
      acks[id] = (jsonDecode(r.body) as Json)['sha256']! as String;
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  }
}

void main() {
  late FakeCamera camera;
  late MemoryClipStore store;
  late ClipTransfers transfers;
  late List<List<SessionClip>> history;
  var n = 0;

  setUp(() {
    camera = FakeCamera();
    store = MemoryClipStore();
    history = [];
    n = 0;
    transfers = ClipTransfers(
      store: store,
      viewerId: me,
      onChanged: history.add,
      newRequestId: () => 'r${++n}',
      retryDelay: Duration.zero,
    )..api = ViewerApi(client: MockClient(camera.handle), base: Uri.parse('http://cam:8080'), token: 't');
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  SessionClip clip(String requestId) => transfers.clips.firstWhere((c) => c.requestId == requestId);

  test('save → recording → ready → download → sha256 → ack', () async {
    await transfers.save();
    expect(camera.saves.single.toJson(), {'requestId': 'r1', 'preSeconds': 20.0, 'postSeconds': 2.0, 'viewerId': me});
    expect(history.first.single.phase, SessionClipPhase.requesting);
    expect(clip('r1').phase, SessionClipPhase.recording);
    expect(clip('r1').clipId, 'clip-r1');

    transfers.onClipChanged(camera.dto('r1', ClipState.ready));
    expect(clip('r1').phase, SessionClipPhase.downloading);
    await settle();

    final c = clip('r1');
    expect(c.phase, SessionClipPhase.ready);
    expect(c.acked, isTrue);
    expect(c.durationMs, 22000);
    expect(c.stored?.length, camera.file.length);
    expect(store.stored['clip-r1'], camera.file);
    expect(camera.acks, {'clip-r1': camera.sha});
    expect(history.map((h) => h.single.phase).toSet(), {
      SessionClipPhase.requesting,
      SessionClipPhase.recording,
      SessionClipPhase.downloading,
      SessionClipPhase.ready,
    });
  });

  test('a corrupted download is retried; a persistent mismatch fails without ack', () async {
    await transfers.save();
    camera.corruptDownloads = 1;
    transfers.onClipChanged(camera.dto('r1', ClipState.ready));
    await settle();
    expect(camera.downloads, 2);
    expect(clip('r1').phase, SessionClipPhase.ready);

    await transfers.save();
    camera.corruptDownloads = 99;
    transfers.onClipChanged(camera.dto('r2', ClipState.ready));
    await settle();
    expect(clip('r2').phase, SessionClipPhase.failed);
    expect(clip('r2').failure, ClipFailure.checksum);
    expect(camera.acks.containsKey('clip-r2'), isFalse);
    expect(store.stored.containsKey('clip-r2'), isFalse);

    camera.corruptDownloads = 0;
    transfers.retry('r2');
    await settle();
    expect(clip('r2').phase, SessionClipPhase.ready);
    expect(camera.acks['clip-r2'], camera.sha);
  });

  test('POST retries reuse the requestId; giving up marks the clip failed', () async {
    camera.failSaves = 2;
    await transfers.save(seconds: 30);
    expect(camera.saves.map((s) => s.requestId), ['r1', 'r1', 'r1']);
    expect(clip('r1').phase, SessionClipPhase.recording);

    camera.failSaves = 3;
    await transfers.save();
    expect(clip('r2').phase, SessionClipPhase.failed);
    expect(clip('r2').failure, ClipFailure.request);
  });

  test('saves never wait for each other or for downloads; newest first', () async {
    camera.downloadGate = Completer();
    await transfers.save();
    transfers.onClipChanged(camera.dto('r1', ClipState.ready));
    await settle();
    expect(clip('r1').phase, SessionClipPhase.downloading);

    camera.saveGate = Completer();
    unawaited(transfers.save(seconds: 10));
    unawaited(transfers.save(seconds: 60));
    await settle();
    expect(transfers.clips.map((c) => c.requestId), ['r3', 'r2', 'r1']);
    expect(camera.saves.map((s) => s.preSeconds), [20, 10, 60]);

    camera.saveGate!.complete();
    camera.downloadGate!.complete();
    await settle();
    expect(clip('r1').phase, SessionClipPhase.ready);
    expect(clip('r2').phase, SessionClipPhase.recording);
    expect(clip('r3').phase, SessionClipPhase.recording);
  });

  test('ready may arrive before the POST response', () async {
    camera.saveGate = Completer();
    final saving = transfers.save();
    await settle();
    transfers.onClipChanged(camera.dto('r1', ClipState.ready));
    camera.saveGate!.complete();
    await saving;
    await settle();
    expect(clip('r1').phase, SessionClipPhase.ready);
    expect(camera.downloads, 1);
  });

  test('clips of other viewers are ignored; mine from an earlier page load are adopted', () async {
    transfers.onClipChanged(camera.dto('other', ClipState.ready, requestedBy: 'someone-else'));
    await settle();
    expect(transfers.clips, isEmpty);
    expect(camera.downloads, 0);

    transfers.onClipChanged(camera.dto('old', ClipState.ready));
    await settle();
    expect(clip('old').phase, SessionClipPhase.ready);
    expect(camera.acks.keys, ['clip-old']);
  });

  test('duplicate ready events download once; expiry fails a pending clip', () async {
    camera.downloadGate = Completer();
    await transfers.save();
    transfers.onClipChanged(camera.dto('r1', ClipState.ready));
    transfers.onClipChanged(camera.dto('r1', ClipState.ready));
    camera.downloadGate!.complete();
    await settle();
    expect(camera.downloads, 1);

    await transfers.save();
    transfers.onClipChanged(camera.dto('r2', ClipState.expired));
    expect(clip('r2').phase, SessionClipPhase.failed);
    expect(clip('r2').failure, ClipFailure.expired);
  });

  test('presets: default 20 s, quick 10/30/60 s, post-roll 2 s', () {
    const p = SavePresets();
    expect(p.defaultSeconds, 20);
    expect(p.quickSeconds, [10, 30, 60]);
    final r = p.request(requestId: 'x', viewerId: me);
    expect((r.preSeconds, r.postSeconds, r.viewerId), (20.0, 2.0, me));
    expect(p.request(requestId: 'x', viewerId: me, seconds: 60).preSeconds, 60);
  });
}

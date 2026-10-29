import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/live/live_signaling.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _Peer implements LivePeer {
  _Peer(this.onState);

  final void Function(LivePeerState) onState;
  final remote = <String>[];
  bool disposed = false;

  @override
  Future<void> addRemoteCandidate(RtcIce c) async => remote.add(c.candidate);

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<String> createAnswer() async => 'ANSWER';

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<void> setRemoteOffer(String sdp) async {}
}

const camera = CameraInfo(protocolVersion: protocolVersion, cameraId: 'cam', name: 'Pitch');

/// End to end through the providers: pairing state from prefs → link → live view and clips.
void main() {
  late List<FakeChannel> channels;
  late List<_Peer> peers;
  late MemoryClipStore store;
  final file = utf8.encode('fake mp4 bytes');

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({
      'viewer.id': 'me',
      'viewer.lastCamera': 'http://cam:8080',
      'viewer.token.http://cam:8080': 'tok',
    });
    final prefs = await SharedPreferences.getInstance();
    channels = [];
    peers = [];
    store = MemoryClipStore();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      pageUriProvider.overrideWithValue(null),
      clipStoreProvider.overrideWithValue(store),
      viewerHttpClientProvider.overrideWithValue(MockClient((r) async {
        if (r.url.path == Api.info) return http.Response(jsonEncode(camera.toJson()), 200);
        if (r.url.path == Api.clips && r.method == 'GET') return http.Response('[]', 200);
        if (r.url.path == Api.clips && r.method == 'POST') {
          final req = SaveClipRequest.fromJson(jsonDecode(r.body) as Json);
          return http.Response(
            jsonEncode(ClipDto(
              id: 'c1',
              requestId: req.requestId,
              state: ClipState.recording,
              createdAtMs: 0,
              requestedBy: req.viewerId,
            ).toJson()),
            202,
          );
        }
        if (r.url.path == Api.clip('c1')) return http.Response.bytes(file, 200);
        if (r.url.path == Api.ack('c1')) return http.Response('', 204);
        return http.Response('', 404);
      })),
      channelConnectorProvider.overrideWithValue((uri) async {
        final ch = FakeChannel();
        channels.add(ch);
        return ch;
      }),
      livePeerFactoryProvider.overrideWithValue(({required onLocalCandidate, required onState}) async {
        final p = _Peer(onState);
        peers.add(p);
        return p;
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(viewerSetupProvider, (_, _) {});
    c.listen(liveViewProvider, (_, _) {});
    c.listen(viewerClipsProvider, (_, _) {});
    return c;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  List<WsMessage> sent(FakeChannel ch) => ch.sent.map((s) => WsMessage.decode(s)!).toList();

  test('welcome starts the live view; offer → answer with trickle ICE; failure restarts', () async {
    final c = await container();
    await until(() => channels.isNotEmpty);
    final ch = channels.single;
    ch.push(const Welcome(camera: camera).encode());
    await until(() => sent(ch).any((m) => m is LiveStart));
    expect(c.read(liveViewProvider).phase, LivePhase.negotiating);

    ch.push(const RtcIce(candidate: 'early').encode());
    ch.push(const RtcOffer(sdp: 'OFFER').encode());
    await until(() => sent(ch).any((m) => m is RtcAnswer));
    expect(peers.single.remote, ['early']);

    peers.single.onState(LivePeerState.connected);
    expect(c.read(liveViewProvider).phase, LivePhase.playing);

    peers.single.onState(LivePeerState.failed);
    expect(c.read(liveViewProvider).phase, LivePhase.interrupted);
    c.read(liveViewProvider.notifier).restart();
    await until(() => peers.length == 2);
    expect(peers.first.disposed, isTrue);
    expect(sent(ch).whereType<LiveStart>().length, 2);
    expect(sent(ch).whereType<LiveStop>().length, 1);
  });

  test('save through the providers ends with a stored, acked clip', () async {
    final c = await container();
    await until(() => channels.isNotEmpty);
    final ch = channels.single;
    ch.push(const Welcome(camera: camera).encode());
    await until(() => sent(ch).any((m) => m is LiveStart));

    c.read(viewerClipsProvider.notifier).save(seconds: 10);
    await until(() => c.read(viewerClipsProvider).firstOrNull?.phase == SessionClipPhase.recording);
    final requestId = c.read(viewerClipsProvider).single.requestId;

    ch.push(ClipChanged(
      clip: ClipDto(
        id: 'c1',
        requestId: requestId,
        state: ClipState.ready,
        createdAtMs: 0,
        requestedBy: 'me',
        bytes: file.length,
        sha256: sha256.convert(file).toString(),
      ),
    ).encode());
    await until(() => c.read(viewerClipsProvider).single.acked);
    expect(store.stored['c1'], file);
  });
}

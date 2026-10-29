import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/viewer/live/live_signaling.dart';
import 'package:replay_protocol/replay_protocol.dart';

class FakePeer implements LivePeer {
  final log = <String>[];
  Completer<void>? remoteGate;

  @override
  Future<void> setRemoteOffer(String sdp) async {
    log.add('offer:$sdp');
    await remoteGate?.future;
  }

  @override
  Future<String> createAnswer() async {
    log.add('answer');
    return 'ANSWER';
  }

  @override
  Future<void> addRemoteCandidate(RtcIce c) async => log.add('ice:${c.candidate}');

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<void> dispose() async {}
}

RtcIce ice(String c) => RtcIce(candidate: c, sdpMid: '0', sdpMLineIndex: 0);

void main() {
  late List<WsMessage> sent;
  late LiveSignaling sig;
  late FakePeer peer;

  setUp(() {
    sent = [];
    sig = LiveSignaling(send: sent.add);
    peer = FakePeer();
    sig.attach(peer);
  });

  test('remote candidates before the offer are queued, then applied before the answer', () async {
    await sig.onRemoteCandidate(ice('a'));
    await sig.onRemoteCandidate(ice('b'));
    expect(sig.queuedRemote, 2);
    expect(peer.log, isEmpty);

    await sig.onOffer('OFFER');
    expect(peer.log, ['offer:OFFER', 'ice:a', 'ice:b', 'answer']);
    expect(sig.queuedRemote, 0);
    expect(sent.single, isA<RtcAnswer>().having((a) => a.sdp, 'sdp', 'ANSWER'));

    await sig.onRemoteCandidate(ice('c'));
    expect(peer.log.last, 'ice:c');
  });

  test('candidates that arrive while the offer is being applied are not lost', () async {
    peer.remoteGate = Completer();
    final offer = sig.onOffer('OFFER');
    await sig.onRemoteCandidate(ice('late'));
    expect(sig.queuedRemote, 1);
    peer.remoteGate!.complete();
    await offer;
    expect(peer.log, ['offer:OFFER', 'ice:late', 'answer']);
  });

  test('local candidates are held until the answer is sent', () async {
    sig.onLocalCandidate(ice('l1'));
    expect(sent, isEmpty);
    await sig.onOffer('OFFER');
    expect(sent.map((m) => m.type), [RtcAnswer.typeName, RtcIce.typeName]);
    sig.onLocalCandidate(ice('l2'));
    expect((sent.last as RtcIce).candidate, 'l2');
  });

  test('a new peer starts with empty queues; a detached one is ignored', () async {
    await sig.onRemoteCandidate(ice('old'));
    final next = FakePeer();
    sig.attach(next);
    expect(sig.queuedRemote, 0);
    await sig.onOffer('O2');
    expect(next.log, ['offer:O2', 'answer']);

    sig.detach();
    await sig.onOffer('O3');
    await sig.onRemoteCandidate(ice('x'));
    sig.onLocalCandidate(ice('y'));
    expect(next.log, ['offer:O2', 'answer']);
    expect(sent.length, 1);
  });

  test('a peer replaced while its offer is pending does not send a stale answer', () async {
    peer.remoteGate = Completer();
    final offer = sig.onOffer('OFFER');
    sig.attach(FakePeer());
    peer.remoteGate!.complete();
    await offer;
    expect(sent, isEmpty);
  });
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:replay_protocol/replay_protocol.dart';

enum LivePeerState { connecting, connected, disconnected, failed, closed }

/// The receive-only WebRTC peer of the live view, behind an interface so the signaling logic is
/// testable without a browser or libwebrtc.
abstract class LivePeer {
  /// Applies the Camera's offer.
  Future<void> setRemoteOffer(String sdp);

  /// Creates the answer and sets it as the local description. Returns its SDP.
  Future<String> createAnswer();

  Future<void> addRemoteCandidate(RtcIce candidate);

  /// The video, letterboxed.
  Widget buildView();

  Future<void> dispose();
}

/// Creates a peer. [onLocalCandidate] gets trickled candidates; [onState] the connection state.
typedef LivePeerFactory = Future<LivePeer> Function({
  required void Function(RtcIce candidate) onLocalCandidate,
  required void Function(LivePeerState state) onState,
});

/// Answer side of the live-view call with trickle ICE (SPEC §4.2): the Camera offers, the Viewer
/// answers. Remote candidates that arrive before the offer is applied are queued; local candidates
/// are held until the answer has been sent, so the Camera never sees a candidate before the answer.
class LiveSignaling {
  LiveSignaling({required this.send});

  final void Function(WsMessage message) send;

  LivePeer? _peer;
  bool _remoteSet = false;
  bool _answerSent = false;
  final _remoteQueue = <RtcIce>[];
  final _localQueue = <RtcIce>[];

  /// Remote candidates waiting for the remote description.
  int get queuedRemote => _remoteQueue.length;

  bool get hasRemoteDescription => _remoteSet;

  /// Starts a new negotiation on [peer], dropping any state from a previous one.
  void attach(LivePeer peer) {
    detach();
    _peer = peer;
  }

  /// Forgets the current peer; late callbacks from it are ignored.
  void detach() {
    _peer = null;
    _remoteSet = false;
    _answerSent = false;
    _remoteQueue.clear();
    _localQueue.clear();
  }

  Future<void> onOffer(String sdp) async {
    final peer = _peer;
    if (peer == null) return;
    await peer.setRemoteOffer(sdp);
    if (!identical(peer, _peer)) return;
    _remoteSet = true;
    final queued = List.of(_remoteQueue);
    _remoteQueue.clear();
    for (final c in queued) {
      await peer.addRemoteCandidate(c);
    }
    final answer = await peer.createAnswer();
    if (!identical(peer, _peer)) return;
    send(RtcAnswer(sdp: answer));
    _answerSent = true;
    for (final c in _localQueue) {
      send(c);
    }
    _localQueue.clear();
  }

  Future<void> onRemoteCandidate(RtcIce candidate) async {
    final peer = _peer;
    if (peer == null) return;
    if (!_remoteSet) {
      _remoteQueue.add(candidate);
      return;
    }
    await peer.addRemoteCandidate(candidate);
  }

  void onLocalCandidate(RtcIce candidate) {
    if (_peer == null) return;
    if (_answerSent) {
      send(candidate);
    } else {
      _localQueue.add(candidate);
    }
  }
}

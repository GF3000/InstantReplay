import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:replay_protocol/replay_protocol.dart';

import 'live_signaling.dart';

/// [LivePeerFactory] backed by `flutter_webrtc` (browser WebRTC on web, libwebrtc on Android).
Future<LivePeer> createWebRtcLivePeer({
  required void Function(RtcIce candidate) onLocalCandidate,
  required void Function(LivePeerState state) onState,
}) async {
  final renderer = RTCVideoRenderer();
  await renderer.initialize();
  // LAN only: no STUN/TURN (SPEC §4); host candidates are enough.
  final pc = await createPeerConnection({'iceServers': <Object>[], 'sdpSemantics': 'unified-plan'});
  final peer = _WebRtcLivePeer(pc, renderer);
  pc.onIceCandidate = (c) {
    final candidate = c.candidate;
    if (candidate == null || candidate.isEmpty) return;
    onLocalCandidate(RtcIce(candidate: candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex));
  };
  pc.onConnectionState = (s) {
    final mapped = switch (s) {
      RTCPeerConnectionState.RTCPeerConnectionStateConnected => LivePeerState.connected,
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => LivePeerState.disconnected,
      RTCPeerConnectionState.RTCPeerConnectionStateFailed => LivePeerState.failed,
      RTCPeerConnectionState.RTCPeerConnectionStateClosed => LivePeerState.closed,
      _ => LivePeerState.connecting,
    };
    if (!peer._disposed) onState(mapped);
  };
  pc.onTrack = (event) async {
    if (event.track.kind != 'video' || peer._disposed) return;
    if (event.streams.isNotEmpty) {
      renderer.srcObject = event.streams.first;
    } else {
      // The offer may carry a track without a stream id.
      final stream = await createLocalMediaStream('live');
      await stream.addTrack(event.track);
      renderer.srcObject = stream;
    }
  };
  return peer;
}

class _WebRtcLivePeer implements LivePeer {
  _WebRtcLivePeer(this._pc, this._renderer);

  final RTCPeerConnection _pc;
  final RTCVideoRenderer _renderer;
  bool _disposed = false;

  @override
  Future<void> setRemoteOffer(String sdp) => _pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

  @override
  Future<String> createAnswer() async {
    final answer = await _pc.createAnswer({'offerToReceiveVideo': true, 'offerToReceiveAudio': false});
    await _pc.setLocalDescription(answer);
    return answer.sdp!;
  }

  @override
  Future<void> addRemoteCandidate(RtcIce c) =>
      _pc.addCandidate(RTCIceCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex));

  @override
  Widget buildView() => RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _renderer.srcObject = null;
    await _pc.close();
    await _renderer.dispose();
  }
}

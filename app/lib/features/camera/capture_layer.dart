import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

/// What the Camera role needs from the capture plugin. Tests replace it with a fake so they never
/// touch platform channels.
abstract interface class CaptureLayer {
  Stream<CaptureStats> get stats;
  Stream<ThermalEvent> get thermal;
  Stream<String> get cameraState;
  Stream<String> get errors;

  /// Camera permission; true when granted.
  Future<bool> requestCameraPermission();

  /// Notification permission (Android 13+) for the recording notice; true when granted.
  /// Capture starts whatever the answer.
  Future<bool> requestNotificationPermission();

  Future<List<CaptureProfile>> supportedProfiles();

  /// [broadcast] starts in broadcast mode (SPEC §12): the program encoder can then be started.
  Future<StartResult> start(String profileId, {bool broadcast = false});

  Future<void> stop();

  Future<void> setPreviewEnabled(bool enabled);

  /// Sensor zoom, 1…[StartResult.maxZoom]; glides to the new value.
  Future<void> setZoom(double ratio);

  /// Replay reserve size (SPEC §3.4); 0 deletes clips on ACK.
  Future<void> setClipReserve(int size);

  /// Completes when the clip is ready, after [postSeconds] of post-roll. A repeated [requestId]
  /// returns the existing clip instead of cutting a new one.
  Future<ClipInfo> saveClip({required String requestId, required double preSeconds, double postSeconds = 0});

  /// Every outbox state change (recording, ready, acked, expired).
  Stream<ClipInfo> get clipChanges;

  /// Clips currently in the outbox (recording or ready).
  Future<List<ClipInfo>> listClips();

  Future<ClipInfo?> getClip(String id);

  /// Releases a clip after the Viewer verified it; false if the hash does not match.
  Future<bool> ackClip(String id, String sha256);

  /// Local ICE candidates to forward to each viewer (trickle ICE).
  Stream<LiveIceCandidate> get liveIceCandidates;

  /// Send-only WebRTC offer for [viewerId], returned right away; candidates follow on
  /// [liveIceCandidates].
  Future<String> liveOffer(String viewerId, {String codec = 'H264'});

  Future<void> liveAnswer(String viewerId, String sdp);

  Future<void> liveAddIceCandidate(String viewerId, String candidate, {String? sdpMid, int? sdpMLineIndex});

  Future<void> liveClose(String viewerId);

  // Full-session recording (SPEC §3.8).

  Stream<RecordingStatus> get recording;

  Stream<RecordingSaved> get recordingSaved;

  Future<RecordingStatus> recordingStatus();

  /// Starts or resumes; [includeSeconds] > 0 also keeps that much of the buffer.
  Future<RecordingStatus> recordStart({int includeSeconds = 0});

  Future<RecordingStatus> recordPause();

  /// Null when nothing was recording.
  Future<RecordingSaved?> recordStop();

  Future<List<RecordingSaved>> recoverRecordings();

  // Broadcast mode (SPEC §12). Only while capture runs with `broadcast: true`.

  /// RECORD_AUDIO; true when granted.
  Future<bool> requestMicPermission();

  /// What the scoreboard overlay shows. Cheap; call on every change.
  Future<void> setOverlay(OverlayState overlay);

  /// Returns once connecting has started; progress arrives on [broadcast].
  Future<BroadcastStatus> broadcastStart(BroadcastConfig config);

  Future<void> broadcastStop();

  Future<BroadcastStatus> broadcastStatus();

  /// Broadcast state changes; the latest numbers also ride on [stats].
  Stream<BroadcastStatus> get broadcast;

  // Replays on air (SPEC §12.6). Only while a broadcast is active.

  /// Puts [clipId] on air at [speed] with [label] drawn over it; completes on the first decoded
  /// frame. PlatformException codes: `not_live`, `replay_unavailable`, `replay_failed`.
  /// [scoreboard]: keep the scoreboard over the replay (off: only the [label] badge).
  Future<ReplayStatus> replayStart(String clipId, {double speed = 1, required String label, bool scoreboard = false});

  Future<void> replaySpeed(double speed);

  /// Back to the camera; [replayEnded] follows.
  Future<void> replayStop();

  /// A replay went on air or changed speed; the position also rides on [stats].
  Stream<ReplayStatus> get replay;

  /// The program is back on the camera; `error` set for a failure.
  Stream<({String clipId, String? error})> get replayEnded;
}

/// The real plugin. Only constructed on Android: the /camera route is unreachable elsewhere.
class PluginCaptureLayer implements CaptureLayer {
  ReplayCapture get _capture => ReplayCapture.instance;

  @override
  Stream<CaptureStats> get stats => _capture.stats;

  @override
  Stream<ThermalEvent> get thermal => _capture.thermal;

  @override
  Stream<String> get cameraState => _capture.cameraState;

  @override
  Stream<String> get errors => _capture.errors;

  @override
  Future<bool> requestCameraPermission() => _capture.requestPermission();

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      // Granted without a prompt below Android 13.
      return (await Permission.notification.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<CaptureProfile>> supportedProfiles() => _capture.supportedProfiles();

  @override
  Future<StartResult> start(String profileId, {bool broadcast = false}) =>
      _capture.start(profileId, broadcast: broadcast);

  @override
  Future<void> stop() => _capture.stop();

  @override
  Future<void> setPreviewEnabled(bool enabled) => _capture.setPreviewEnabled(enabled);

  @override
  Future<void> setZoom(double ratio) => _capture.setZoom(ratio);

  @override
  Future<void> setClipReserve(int size) => _capture.setClipReserve(size);

  @override
  Future<ClipInfo> saveClip({required String requestId, required double preSeconds, double postSeconds = 0}) =>
      _capture.saveClip(requestId: requestId, preSeconds: preSeconds, postSeconds: postSeconds);

  @override
  Stream<ClipInfo> get clipChanges => _capture.clipChanges;

  @override
  Future<List<ClipInfo>> listClips() => _capture.listClips();

  @override
  Future<ClipInfo?> getClip(String id) => _capture.getClip(id);

  @override
  Future<bool> ackClip(String id, String sha256) => _capture.ackClip(id, sha256);

  @override
  Stream<LiveIceCandidate> get liveIceCandidates => _capture.liveIceCandidates;

  @override
  Future<String> liveOffer(String viewerId, {String codec = 'H264'}) => _capture.liveOffer(viewerId, codec: codec);

  @override
  Future<void> liveAnswer(String viewerId, String sdp) => _capture.liveAnswer(viewerId, sdp);

  @override
  Future<void> liveAddIceCandidate(String viewerId, String candidate, {String? sdpMid, int? sdpMLineIndex}) =>
      _capture.liveAddIceCandidate(viewerId, candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex);

  @override
  Future<void> liveClose(String viewerId) => _capture.liveClose(viewerId);

  @override
  Stream<RecordingStatus> get recording => _capture.recording;

  @override
  Stream<RecordingSaved> get recordingSaved => _capture.recordingSaved;

  @override
  Future<RecordingStatus> recordingStatus() => _capture.recordingStatus();

  @override
  Future<RecordingStatus> recordStart({int includeSeconds = 0}) => _capture.recordStart(includeSeconds: includeSeconds);

  @override
  Future<RecordingStatus> recordPause() => _capture.recordPause();

  @override
  Future<RecordingSaved?> recordStop() => _capture.recordStop();

  @override
  Future<List<RecordingSaved>> recoverRecordings() => _capture.recoverRecordings();

  @override
  Future<bool> requestMicPermission() => _capture.requestMicPermission();

  @override
  Future<void> setOverlay(OverlayState overlay) => _capture.setOverlay(overlay);

  @override
  Future<BroadcastStatus> broadcastStart(BroadcastConfig config) => _capture.broadcastStart(config);

  @override
  Future<void> broadcastStop() => _capture.broadcastStop();

  @override
  Future<BroadcastStatus> broadcastStatus() => _capture.broadcastStatus();

  @override
  Stream<BroadcastStatus> get broadcast => _capture.broadcast;

  @override
  Future<ReplayStatus> replayStart(String clipId, {double speed = 1, required String label, bool scoreboard = false}) =>
      _capture.replayStart(clipId, speed: speed, label: label, scoreboard: scoreboard);

  @override
  Future<void> replaySpeed(double speed) => _capture.replaySpeed(speed);

  @override
  Future<void> replayStop() => _capture.replayStop();

  @override
  Stream<ReplayStatus> get replay => _capture.replay;

  @override
  Stream<({String clipId, String? error})> get replayEnded => _capture.replayEnded;
}

final captureLayerProvider = Provider<CaptureLayer>((ref) => PluginCaptureLayer());

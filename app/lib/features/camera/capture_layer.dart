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

  Future<StartResult> start(String profileId);

  Future<void> stop();

  Future<void> setPreviewEnabled(bool enabled);

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
  Future<StartResult> start(String profileId) => _capture.start(profileId);

  @override
  Future<void> stop() => _capture.stop();

  @override
  Future<void> setPreviewEnabled(bool enabled) => _capture.setPreviewEnabled(enabled);

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
}

final captureLayerProvider = Provider<CaptureLayer>((ref) => PluginCaptureLayer());

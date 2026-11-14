import 'dart:async';

import 'src/capture_api.g.dart';

export 'src/capture_api.g.dart'
    show
        BroadcastConfig,
        BroadcastState,
        BroadcastStatus,
        CaptureProfile,
        CaptureStats,
        ClipInfo,
        ClipState,
        LiveViewerStats,
        OverlayState,
        OverlayStyle,
        RecordingEnd,
        RecordingSaved,
        RecordingState,
        RecordingStatus,
        ReplayStatus,
        SaveRequest,
        StartRequest,
        StartResult,
        ThermalAction,
        ThermalEvent;

/// Dart facade over the native capture pipeline (camera → GL → H.264 → fMP4 ring buffer → outbox).
class ReplayCapture implements CaptureEventsApi {
  ReplayCapture._() {
    CaptureEventsApi.setUp(this);
  }

  static final instance = ReplayCapture._();

  final _host = CaptureHostApi();
  final _stats = StreamController<CaptureStats>.broadcast();
  final _thermal = StreamController<ThermalEvent>.broadcast();
  final _cameraState = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _clips = StreamController<ClipInfo>.broadcast();
  final _liveIce = StreamController<LiveIceCandidate>.broadcast();
  final _liveState = StreamController<({String viewerId, String state})>.broadcast();
  final _recording = StreamController<RecordingStatus>.broadcast();
  final _recordingSaved = StreamController<RecordingSaved>.broadcast();
  final _broadcast = StreamController<BroadcastStatus>.broadcast();
  final _replay = StreamController<ReplayStatus>.broadcast();
  final _replayEnded = StreamController<({String clipId, String? error})>.broadcast();

  /// About once per second while capturing.
  Stream<CaptureStats> get stats => _stats.stream;
  Stream<ThermalEvent> get thermal => _thermal.stream;
  Stream<String> get cameraState => _cameraState.stream;
  Stream<String> get errors => _errors.stream;

  /// Every outbox state change (recording, ready, acked, expired).
  Stream<ClipInfo> get clipChanges => _clips.stream;

  /// Local ICE candidates to forward to each viewer (trickle ICE).
  Stream<LiveIceCandidate> get liveIceCandidates => _liveIce.stream;

  /// PeerConnection state per viewer.
  Stream<({String viewerId, String state})> get liveStates => _liveState.stream;

  /// Recording state changes; the latest state also rides on every [stats] event.
  Stream<RecordingStatus> get recording => _recording.stream;

  Stream<RecordingSaved> get recordingSaved => _recordingSaved.stream;

  /// Broadcast state changes (SPEC §12); the latest numbers also ride on every [stats] event.
  Stream<BroadcastStatus> get broadcast => _broadcast.stream;

  /// A replay went on air or changed speed (SPEC §12.6).
  Stream<ReplayStatus> get replay => _replay.stream;

  /// The program is back on the camera; [error] set for a failure.
  Stream<({String clipId, String? error})> get replayEnded => _replayEnded.stream;

  Future<bool> requestPermission() => _host.requestPermission();

  Future<List<CaptureProfile>> supportedProfiles() => _host.supportedProfiles();

  Future<bool> requestMicPermission() => _host.requestMicPermission();

  Future<bool> micPermissionGranted() => _host.micPermissionGranted();

  /// [broadcast] starts in broadcast mode (SPEC §12): the program encoder can then be started.
  Future<StartResult> start(String profileId, {int windowSeconds = 80, bool broadcast = false}) =>
      _host.start(StartRequest(profileId: profileId, windowSeconds: windowSeconds, broadcast: broadcast));

  Future<void> stop() => _host.stop();

  Future<void> setPreviewEnabled(bool enabled) => _host.setPreviewEnabled(enabled);

  Future<void> setZoom(double ratio) => _host.setZoom(ratio);

  /// Completes when the clip is ready, after [postSeconds] of post-roll.
  Future<ClipInfo> saveClip({required String requestId, required double preSeconds, double postSeconds = 0}) =>
      _host.saveClip(SaveRequest(requestId: requestId, preSeconds: preSeconds, postSeconds: postSeconds));

  Future<List<ClipInfo>> listClips() => _host.listClips();

  Future<ClipInfo?> getClip(String id) => _host.getClip(id);

  Future<bool> ackClip(String id, String sha256) => _host.ackClip(id, sha256);

  /// Replay reserve size (SPEC §3.4); 0 deletes clips on ACK.
  Future<void> setClipReserve(int size) => _host.setClipReserve(size);

  /// The offer comes back right away; candidates follow on [liveIceCandidates].
  Future<String> liveOffer(String viewerId, {String codec = 'H264'}) => _host.liveOffer(viewerId, codec);

  Future<void> liveAnswer(String viewerId, String sdp) => _host.liveAnswer(viewerId, sdp);

  Future<void> liveAddIceCandidate(String viewerId, String candidate, {String? sdpMid, int? sdpMLineIndex}) =>
      _host.liveAddIceCandidate(viewerId, candidate, sdpMid, sdpMLineIndex);

  Future<void> liveClose(String viewerId) => _host.liveClose(viewerId);

  Future<List<LiveViewerStats>> liveStats() => _host.liveStats();

  Future<RecordingStatus> recordingStatus() => _host.recordingStatus();

  Future<RecordingStatus> recordStart({int includeSeconds = 0}) => _host.recordStart(includeSeconds);

  Future<RecordingStatus> recordPause() => _host.recordPause();

  Future<RecordingSaved?> recordStop() => _host.recordStop();

  Future<List<RecordingSaved>> recoverRecordings() => _host.recoverRecordings();

  /// What the scoreboard overlay shows; call on every change (broadcast mode only).
  Future<void> setOverlay(OverlayState overlay) => _host.setOverlay(overlay);

  /// Returns once connecting has started; progress arrives on [broadcast].
  Future<BroadcastStatus> broadcastStart(BroadcastConfig config) => _host.broadcastStart(config);

  Future<void> broadcastStop() => _host.broadcastStop();

  Future<BroadcastStatus> broadcastStatus() => _host.broadcastStatus();

  /// Microphone on air on/off, live; false when it cannot be turned on.
  Future<bool> broadcastSetAudio(bool audio) => _host.broadcastSetAudio(audio);

  /// The stream's microphone level in dBFS (−90…0, muted or not); null without an open mic.
  /// Cheap; poll ~10 Hz while a meter is shown.
  Future<double?> broadcastMicLevel() => _host.broadcastMicLevel();

  /// [scoreboard]: keep the scoreboard over the replay (off: only the [label] badge).
  Future<ReplayStatus> replayStart(String clipId, {double speed = 1, required String label, bool scoreboard = false}) =>
      _host.replayStart(clipId, speed, label, scoreboard);

  Future<void> replaySpeed(double speed) => _host.replaySpeed(speed);

  Future<void> replayStop() => _host.replayStop();

  @override
  void onStats(CaptureStats stats) => _stats.add(stats);

  @override
  void onThermal(ThermalEvent event) => _thermal.add(event);

  @override
  void onCameraState(String state) => _cameraState.add(state);

  @override
  void onError(String message) => _errors.add(message);

  @override
  void onClipChanged(ClipInfo clip) => _clips.add(clip);

  @override
  void onLiveIceCandidate(String viewerId, String candidate, String? sdpMid, int? sdpMLineIndex) => _liveIce
      .add((viewerId: viewerId, candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex));

  @override
  void onLiveState(String viewerId, String state) => _liveState.add((viewerId: viewerId, state: state));

  @override
  void onRecording(RecordingStatus status) => _recording.add(status);

  @override
  void onRecordingSaved(RecordingSaved saved) => _recordingSaved.add(saved);

  @override
  void onBroadcast(BroadcastStatus status) => _broadcast.add(status);

  @override
  void onReplay(ReplayStatus status) => _replay.add(status);

  @override
  void onReplayEnded(String clipId, String? error) => _replayEnded.add((clipId: clipId, error: error));
}

typedef LiveIceCandidate = ({String viewerId, String candidate, String? sdpMid, int? sdpMLineIndex});

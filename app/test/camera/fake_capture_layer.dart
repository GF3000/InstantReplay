import 'dart:async';

import 'package:instant_replay/features/camera/capture_layer.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

CaptureProfile profile(String id, {int width = 1920, int height = 1080, int fps = 30}) =>
    CaptureProfile(id: id, width: width, height: height, fps: fps, bitrate: 20000000);

CaptureStats stats({
  int bufferMs = 42000,
  int outboxClips = 3,
  double? batteryTempC = 36.5,
  bool plugged = true,
  RecordingStatus? recording,
}) =>
    CaptureStats(
      encodedFrames: 1000,
      fps: 30,
      gaps: 0,
      cameraGaps: 0,
      glGaps: 0,
      bufferMs: bufferMs,
      bufferBytes: 100000000,
      outboxClips: outboxClips,
      outboxBytes: 30000000,
      thermalStatus: 0,
      plugged: plugged,
      batteryTempC: batteryTempC,
      batteryPercent: 80,
      recording: recording,
    );

/// In-memory capture layer that records every call.
class FakeCaptureLayer implements CaptureLayer {
  FakeCaptureLayer({
    List<CaptureProfile>? profiles,
    this.cameraGranted = true,
    this.notificationsGranted = true,
  }) : profiles = profiles ?? [profile('720p30', width: 1280, height: 720), profile('1080p30'), profile('1080p60', fps: 60)];

  final List<CaptureProfile> profiles;
  bool cameraGranted;
  bool notificationsGranted;
  Object? startError;

  final calls = <String>[];
  final statsController = StreamController<CaptureStats>.broadcast();
  final thermalController = StreamController<ThermalEvent>.broadcast();
  final cameraStateController = StreamController<String>.broadcast();
  final errorsController = StreamController<String>.broadcast();

  List<String> get starts => [for (final c in calls) if (c.startsWith('start:')) c.substring(6)];

  @override
  Stream<CaptureStats> get stats => statsController.stream;

  @override
  Stream<ThermalEvent> get thermal => thermalController.stream;

  @override
  Stream<String> get cameraState => cameraStateController.stream;

  @override
  Stream<String> get errors => errorsController.stream;

  @override
  Future<bool> requestCameraPermission() async {
    calls.add('cameraPermission');
    return cameraGranted;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('notificationPermission');
    return notificationsGranted;
  }

  @override
  Future<List<CaptureProfile>> supportedProfiles() async => profiles;

  /// The `broadcast` flag of every start, in order.
  final startModes = <bool>[];

  @override
  Future<StartResult> start(String profileId, {bool broadcast = false}) async {
    calls.add('start:$profileId');
    startModes.add(broadcast);
    final error = startError;
    if (error != null) throw error;
    return StartResult(textureId: 7, encoder: 'fake', highProfile: true, sensorOrientation: 90, maxZoom: 10);
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> setPreviewEnabled(bool enabled) async => calls.add('preview:$enabled');

  @override
  Future<void> setZoom(double ratio) async => calls.add('zoom:$ratio');

  @override
  Future<void> setClipReserve(int size) async {
    calls.add('reserve:$size');
    reserveSize = size;
  }

  /// Replay reserve (SPEC §3.4): acked clips keep their file while > 0.
  int reserveSize = 0;

  @override
  Future<ClipInfo> saveClip({required String requestId, required double preSeconds, double postSeconds = 0}) {
    calls.add('save:$preSeconds');
    final existing = outbox.values.where((c) => c.requestId == requestId).firstOrNull;
    if (existing != null) {
      return _pendingSaves[existing.id]?.future ?? Future.value(existing);
    }
    final id = 'clip${_nextClip++}';
    final clip = ClipInfo(id: id, requestId: requestId, state: ClipState.recording, createdAtMs: 1000);
    outbox[id] = clip;
    clipChangesController.add(clip);
    if (autoFinishClips) {
      return Future.value(finishClip(id, durationMs: 20000, bytes: 50000000));
    }
    return (_pendingSaves[id] = Completer<ClipInfo>()).future;
  }

  /// Outbox keyed by clip id. [saveClip] adds a `recording` clip and emits it on [clipChanges];
  /// it completes when a test calls [finishClip] (or right away with [autoFinishClips]).
  final outbox = <String, ClipInfo>{};
  final clipChangesController = StreamController<ClipInfo>.broadcast();
  final liveIceController = StreamController<LiveIceCandidate>.broadcast();
  final _pendingSaves = <String, Completer<ClipInfo>>{};

  /// When true, [saveClip] returns a ready clip immediately (the Camera screen's test button).
  bool autoFinishClips = true;

  /// The sha256 [ackClip] accepts for every clip.
  String acceptedSha256 = 'good-hash';

  int _nextClip = 1;

  /// Marks a clip ready, optionally pointing at a real file, and emits the change.
  ClipInfo finishClip(String id, {String? path, int? bytes, int durationMs = 20000, String? sha256}) {
    final clip = ClipInfo(
      id: id,
      requestId: outbox[id]!.requestId,
      state: ClipState.ready,
      createdAtMs: outbox[id]!.createdAtMs,
      path: path,
      bytes: bytes,
      durationMs: durationMs,
      sha256: sha256 ?? acceptedSha256,
    );
    outbox[id] = clip;
    clipChangesController.add(clip);
    _pendingSaves.remove(id)?.complete(clip);
    return clip;
  }

  @override
  Stream<ClipInfo> get clipChanges => clipChangesController.stream;

  @override
  Future<List<ClipInfo>> listClips() async => [
        for (final c in outbox.values)
          if (c.state == ClipState.recording || c.state == ClipState.ready) c,
      ];

  @override
  Future<ClipInfo?> getClip(String id) async => outbox[id];

  @override
  Future<bool> ackClip(String id, String sha256) async {
    calls.add('ack:$id:$sha256');
    final clip = outbox[id];
    if (clip == null || clip.state != ClipState.ready || sha256 != acceptedSha256) return false;
    final acked = ClipInfo(
      id: id,
      requestId: clip.requestId,
      state: ClipState.acked,
      createdAtMs: clip.createdAtMs,
      path: reserveSize > 0 ? clip.path : null,
      bytes: clip.bytes,
      durationMs: clip.durationMs,
      sha256: clip.sha256,
      reserved: reserveSize > 0 ? true : null,
    );
    outbox[id] = acked;
    clipChangesController.add(acked);
    return true;
  }

  @override
  Stream<LiveIceCandidate> get liveIceCandidates => liveIceController.stream;

  /// Called from [liveOffer] before it returns, e.g. to emit candidates ahead of the offer.
  void Function(String viewerId)? onLiveOffer;

  @override
  Future<String> liveOffer(String viewerId, {String codec = 'H264'}) async {
    calls.add('liveOffer:$viewerId:$codec');
    onLiveOffer?.call(viewerId);
    return 'offer-sdp-$viewerId';
  }

  @override
  Future<void> liveAnswer(String viewerId, String sdp) async => calls.add('liveAnswer:$viewerId:$sdp');

  @override
  Future<void> liveAddIceCandidate(String viewerId, String candidate, {String? sdpMid, int? sdpMLineIndex}) async =>
      calls.add('liveIce:$viewerId:$candidate:$sdpMid:$sdpMLineIndex');

  @override
  Future<void> liveClose(String viewerId) async => calls.add('liveClose:$viewerId');

  // region Recording: an in-memory state machine; tests push status and saved events directly.

  final recordingController = StreamController<RecordingStatus>.broadcast();
  final recordingSavedController = StreamController<RecordingSaved>.broadcast();
  RecordingStatus recordingState = recStatus();
  List<RecordingSaved> toRecover = [];

  /// Thrown by [recordStart] when set, e.g. `PlatformException(code: 'no_space')`.
  Object? recordStartError;

  @override
  Stream<RecordingStatus> get recording => recordingController.stream;

  @override
  Stream<RecordingSaved> get recordingSaved => recordingSavedController.stream;

  @override
  Future<RecordingStatus> recordingStatus() async => recordingState;

  void _setRecording(RecordingStatus s) {
    recordingState = s;
    recordingController.add(s);
  }

  @override
  Future<RecordingStatus> recordStart({int includeSeconds = 0}) async {
    calls.add('recordStart:$includeSeconds');
    if (recordStartError case final e?) throw e;
    _setRecording(recStatus(state: RecordingState.recording, elapsedMs: recordingState.elapsedMs, parts: 1));
    return recordingState;
  }

  @override
  Future<RecordingStatus> recordPause() async {
    calls.add('recordPause');
    _setRecording(recStatus(state: RecordingState.paused, elapsedMs: recordingState.elapsedMs, parts: 1));
    return recordingState;
  }

  @override
  Future<RecordingSaved?> recordStop() async {
    calls.add('recordStop');
    if (recordingState.state == RecordingState.idle) return null;
    final saved = RecordingSaved(
      name: 'InstantReplay_2026-10-30_11-30.mp4',
      parts: recordingState.parts,
      durationMs: recordingState.elapsedMs,
      bytes: recordingState.bytes,
      reason: RecordingEnd.user,
    );
    _setRecording(recStatus());
    recordingSavedController.add(saved);
    return saved;
  }

  @override
  Future<List<RecordingSaved>> recoverRecordings() async {
    calls.add('recoverRecordings');
    final found = toRecover;
    toRecover = [];
    return found;
  }

  // endregion

  // region Broadcast

  bool micGranted = true;
  final overlays = <OverlayState>[];
  final broadcastConfigs = <BroadcastConfig>[];
  final broadcastController = StreamController<BroadcastStatus>.broadcast();
  BroadcastStatus broadcastState = BroadcastStatus(state: BroadcastState.idle, targetKbps: 4500, droppedFrames: 0, audio: true);

  /// Thrown by [broadcastStart] when set.
  Object? broadcastStartError;

  @override
  Future<bool> requestMicPermission() async {
    calls.add('micPermission');
    return micGranted;
  }

  @override
  Future<void> setOverlay(OverlayState overlay) async => overlays.add(overlay);

  @override
  Future<BroadcastStatus> broadcastStart(BroadcastConfig config) async {
    calls.add('broadcastStart');
    if (broadcastStartError case final e?) throw e;
    broadcastConfigs.add(config);
    broadcastState = BroadcastStatus(
        state: BroadcastState.connecting, targetKbps: config.targetKbps, droppedFrames: 0, audio: config.audio);
    broadcastController.add(broadcastState);
    return broadcastState;
  }

  @override
  Future<void> broadcastStop() async {
    calls.add('broadcastStop');
    broadcastState = BroadcastStatus(state: BroadcastState.idle, targetKbps: 4500, droppedFrames: 0, audio: true);
    broadcastController.add(broadcastState);
  }

  @override
  Future<BroadcastStatus> broadcastStatus() async => broadcastState;

  @override
  Stream<BroadcastStatus> get broadcast => broadcastController.stream;

  // endregion
}

RecordingStatus recStatus({
  RecordingState state = RecordingState.idle,
  int elapsedMs = 0,
  int parts = 0,
  int freeBytes = 20000000000,
  int? remainingMs = 36000000,
  bool lowSpace = false,
}) =>
    RecordingStatus(
      state: state,
      elapsedMs: elapsedMs,
      bytes: elapsedMs * 1500,
      parts: parts,
      freeBytes: freeBytes,
      remainingMs: remainingMs,
      lowSpace: lowSpace,
    );

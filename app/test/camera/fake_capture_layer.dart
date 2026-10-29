import 'dart:async';

import 'package:instant_replay/features/camera/capture_layer.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

CaptureProfile profile(String id, {int width = 1920, int height = 1080, int fps = 30}) =>
    CaptureProfile(id: id, width: width, height: height, fps: fps, bitrate: 20000000);

CaptureStats stats({int bufferMs = 42000, int outboxClips = 3, double? batteryTempC = 36.5, bool plugged = true}) =>
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

  @override
  Future<StartResult> start(String profileId) async {
    calls.add('start:$profileId');
    final error = startError;
    if (error != null) throw error;
    return StartResult(textureId: 7, encoder: 'fake', highProfile: true, sensorOrientation: 90);
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> setPreviewEnabled(bool enabled) async => calls.add('preview:$enabled');

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
      bytes: clip.bytes,
      durationMs: clip.durationMs,
      sha256: clip.sha256,
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
}

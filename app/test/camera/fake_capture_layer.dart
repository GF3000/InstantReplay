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
  Future<ClipInfo> saveClip({required String requestId, required double preSeconds}) async {
    calls.add('save:$preSeconds');
    return ClipInfo(
      id: 'clip',
      requestId: requestId,
      state: ClipState.ready,
      createdAtMs: 0,
      durationMs: 20000,
      bytes: 50000000,
    );
  }
}

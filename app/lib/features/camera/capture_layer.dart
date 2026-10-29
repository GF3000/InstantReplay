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

  Future<ClipInfo> saveClip({required String requestId, required double preSeconds});
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
  Future<ClipInfo> saveClip({required String requestId, required double preSeconds}) =>
      _capture.saveClip(requestId: requestId, preSeconds: preSeconds);
}

final captureLayerProvider = Provider<CaptureLayer>((ref) => PluginCaptureLayer());

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/camera/camera_session.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

void main() {
  CaptureProfile p(String id, int w, int h, int fps) =>
      CaptureProfile(id: id, width: w, height: h, fps: fps, bitrate: 1);

  final p1080p60 = p('1080p60', 1920, 1080, 60);
  final p1080p30 = p('1080p30', 1920, 1080, 30);
  final p720p30 = p('720p30', 1280, 720, 30);
  final all = [p1080p60, p1080p30, p720p30];
  final fallback = CameraSessionNotifier.thermalFallback;

  test('reduceFps keeps the resolution', () {
    expect(fallback(all, p1080p60, ThermalAction.reduceFps)?.id, '1080p30');
    expect(fallback(all, p1080p30, ThermalAction.reduceFps), isNull);
  });

  test('reduceResolution drops to the smallest 30 fps profile', () {
    expect(fallback(all, p1080p60, ThermalAction.reduceResolution)?.id, '720p30');
    expect(fallback(all, p1080p30, ThermalAction.reduceResolution)?.id, '720p30');
    expect(fallback(all, p720p30, ThermalAction.reduceResolution), isNull);
  });

  test('preview and bitrate actions never restart capture', () {
    expect(fallback(all, p1080p60, ThermalAction.previewOff), isNull);
    expect(fallback(all, p1080p60, ThermalAction.reduceLiveBitrate), isNull);
  });
}

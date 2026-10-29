import 'package:flutter/services.dart';

/// Encoder/camera profile for the Camera role.
class CaptureProfile {
  const CaptureProfile({
    required this.label,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrate,
  });

  final String label;
  final int width;
  final int height;
  final int fps;
  final int bitrate;

  static const low = CaptureProfile(label: '720p30', width: 1280, height: 720, fps: 30, bitrate: 5000000);
  static const standard =
      CaptureProfile(label: '1080p30', width: 1920, height: 1080, fps: 30, bitrate: 12000000);
  static const high = CaptureProfile(label: '1080p60', width: 1920, height: 1080, fps: 60, bitrate: 20000000);

  static const all = [low, standard, high];
}

class CaptureSession {
  const CaptureSession({
    required this.textureId,
    required this.clipsDir,
    required this.encoder,
    required this.highProfile,
    required this.sensorOrientation,
  });

  final int textureId;
  final String clipsDir;
  final String encoder;
  final bool highProfile;
  final int sensorOrientation;
}

class SavedClip {
  SavedClip.fromMap(Map<Object?, Object?> m)
      : path = m['path']! as String,
        name = m['name']! as String,
        bytes = m['bytes']! as int,
        durationMs = m['durationMs']! as int,
        fragments = m['fragments']! as int,
        assemblyMs = m['assemblyMs']! as int,
        extraPreRollMs = m['extraPreRollMs']! as int;

  final String path;
  final String name;
  final int bytes;
  final int durationMs;
  final int fragments;
  final int assemblyMs;
  final int extraPreRollMs;

  Map<String, Object> toJson() => {
        'name': name,
        'bytes': bytes,
        'durationMs': durationMs,
        'fragments': fragments,
        'assemblyMs': assemblyMs,
        'extraPreRollMs': extraPreRollMs,
      };
}

/// Dart facade over the native capture pipeline (camera → GL → H.264 → fMP4 ring buffer).
class ReplayCapture {
  static const _methods = MethodChannel('instant_replay/capture');
  static const _events = EventChannel('instant_replay/capture/events');

  /// Native events as maps with a `type` key: `stats`, `thermal`, `camera`, `error`.
  static final Stream<Map<Object?, Object?>> events =
      _events.receiveBroadcastStream().map((e) => e as Map<Object?, Object?>);

  static Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  static Future<CaptureSession> start(CaptureProfile profile, {int windowSeconds = 80}) async {
    final r = (await _methods.invokeMapMethod<String, Object?>('start', {
      'width': profile.width,
      'height': profile.height,
      'fps': profile.fps,
      'bitrate': profile.bitrate,
      'windowSeconds': windowSeconds,
    }))!;
    return CaptureSession(
      textureId: r['textureId']! as int,
      clipsDir: r['clipsDir']! as String,
      encoder: r['encoder']! as String,
      highProfile: r['highProfile']! as bool,
      sensorOrientation: r['sensorOrientation']! as int,
    );
  }

  static Future<void> stop() => _methods.invokeMethod('stop');

  /// Waits for [postSeconds] of post-roll, then writes the clip. Resolves when the file is ready.
  static Future<SavedClip> saveClip({required double preSeconds, double postSeconds = 0}) async {
    final r = await _methods.invokeMapMethod<Object?, Object?>('saveClip', {
      'preSeconds': preSeconds,
      'postSeconds': postSeconds,
    });
    return SavedClip.fromMap(r!);
  }

  /// Creates a send-only WebRTC connection for [viewerId]; returns the complete offer SDP
  /// (non-trickle). [codec] is the preferred video codec name, e.g. `H264` or `VP8`.
  static Future<String> liveOffer(String viewerId, {String codec = 'H264'}) async =>
      (await _methods.invokeMethod<String>('liveOffer', {'viewerId': viewerId, 'codec': codec}))!;

  static Future<void> liveAnswer(String viewerId, String sdp) =>
      _methods.invokeMethod('liveAnswer', {'viewerId': viewerId, 'sdp': sdp});

  static Future<void> liveClose(String viewerId) => _methods.invokeMethod('liveClose', {'viewerId': viewerId});

  /// Outbound video stats per viewer (codec, encoder implementation, fps, resolution).
  static Future<List<Object?>> liveStats() async => await _methods.invokeListMethod<Object?>('liveStats') ?? [];
}

// Contract between Dart and the native capture pipeline.
// Regenerate after editing: `dart run pigeon --input pigeons/capture_api.dart` (in this package).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/capture_api.g.dart',
  dartPackageName: 'replay_capture_android',
  kotlinOut: 'android/src/main/kotlin/io/github/instantreplay/replay_capture_android/CaptureApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'io.github.instantreplay.replay_capture_android'),
))

/// An encoder/camera profile the device can run in a regular capture session (SPEC D12).
class CaptureProfile {
  CaptureProfile({
    required this.id,
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrate,
  });

  /// Stable id such as `1080p30`.
  String id;
  int width;
  int height;
  int fps;
  int bitrate;
}

class StartRequest {
  StartRequest({required this.profileId, required this.windowSeconds});

  String profileId;

  /// Ring-buffer window: longest preset + post-roll + margin (SPEC §3.2).
  int windowSeconds;
}

class StartResult {
  StartResult({
    required this.textureId,
    required this.encoder,
    required this.highProfile,
    required this.sensorOrientation,
  });

  /// Flutter texture showing the local preview.
  int textureId;
  String encoder;
  bool highProfile;
  int sensorOrientation;
}

/// Outbox lifecycle (SPEC §3.4).
enum ClipState { recording, ready, acked, expired }

class SaveRequest {
  SaveRequest({required this.requestId, required this.preSeconds, required this.postSeconds});

  /// Client-generated; a repeated id returns the existing clip instead of cutting a new one.
  String requestId;
  double preSeconds;
  double postSeconds;
}

class ClipInfo {
  ClipInfo({
    required this.id,
    required this.requestId,
    required this.state,
    required this.createdAtMs,
    this.path,
    this.bytes,
    this.durationMs,
    this.fragments,
    this.assemblyMs,
    this.extraPreRollMs,
    this.sha256,
  });

  String id;
  String requestId;
  ClipState state;

  /// Wall-clock time of the save request on the Camera.
  int createdAtMs;

  // Set once the clip is ready.
  String? path;
  int? bytes;
  int? durationMs;
  int? fragments;
  int? assemblyMs;
  int? extraPreRollMs;
  String? sha256;
}

class CaptureStats {
  CaptureStats({
    required this.encodedFrames,
    required this.fps,
    required this.gaps,
    required this.cameraGaps,
    required this.glGaps,
    required this.bufferMs,
    required this.bufferBytes,
    required this.outboxClips,
    required this.outboxBytes,
    required this.thermalStatus,
    required this.plugged,
    this.thermalHeadroom,
    this.batteryTempC,
    this.batteryPercent,
  });

  int encodedFrames;
  double fps;

  /// Frame intervals > 1.5× nominal in the HQ stream, and where they came from.
  int gaps;
  int cameraGaps;
  int glGaps;

  int bufferMs;
  int bufferBytes;
  int outboxClips;
  int outboxBytes;

  /// PowerManager.THERMAL_STATUS_* (0 none … 6 shutdown).
  int thermalStatus;
  double? thermalHeadroom;
  double? batteryTempC;
  int? batteryPercent;
  bool plugged;
}

/// Staged degradation applied by the thermal policy (SPEC §3.6).
enum ThermalAction { none, previewOff, reduceLiveBitrate, reduceFps, reduceResolution, stopLive }

class ThermalEvent {
  ThermalEvent({required this.status, required this.action});

  int status;
  ThermalAction action;
}

class LiveViewerStats {
  LiveViewerStats({
    required this.viewerId,
    this.codec,
    this.encoderImplementation,
    this.framesPerSecond,
    this.frameWidth,
    this.frameHeight,
    this.qualityLimitationReason,
  });

  String viewerId;
  String? codec;
  String? encoderImplementation;
  double? framesPerSecond;
  int? frameWidth;
  int? frameHeight;
  String? qualityLimitationReason;
}

@HostApi()
abstract class CaptureHostApi {
  @async
  bool requestPermission();

  /// Profiles the back camera supports in a regular session, best first.
  List<CaptureProfile> supportedProfiles();

  StartResult start(StartRequest request);

  void stop();

  /// Operating mode turns the local preview off to save power and heat.
  void setPreviewEnabled(bool enabled);

  /// Completes when the clip is ready (after the post-roll).
  @async
  ClipInfo saveClip(SaveRequest request);

  /// Clips currently in the outbox (recording or ready).
  List<ClipInfo> listClips();

  ClipInfo? getClip(String id);

  /// Releases a clip after the Viewer verified it. Returns false if the hash does not match.
  bool ackClip(String id, String sha256);

  /// Send-only WebRTC offer for [viewerId]. Returned as soon as it is created; ICE candidates
  /// follow through [CaptureEventsApi.onLiveIceCandidate] (trickle ICE).
  @async
  String liveOffer(String viewerId, String codec);

  @async
  void liveAnswer(String viewerId, String sdp);

  /// A candidate trickled by the viewer.
  void liveAddIceCandidate(String viewerId, String candidate, String? sdpMid, int? sdpMLineIndex);

  void liveClose(String viewerId);

  @async
  List<LiveViewerStats> liveStats();
}

@FlutterApi()
abstract class CaptureEventsApi {
  void onStats(CaptureStats stats);

  void onThermal(ThermalEvent event);

  /// `opening`, `streaming`, `disconnected`, `error`.
  void onCameraState(String state);

  void onError(String message);

  void onClipChanged(ClipInfo clip);

  /// A local ICE candidate for [viewerId]'s connection, to forward to that viewer.
  void onLiveIceCandidate(String viewerId, String candidate, String? sdpMid, int? sdpMLineIndex);

  /// PeerConnection state for [viewerId]: `new`, `connecting`, `connected`, `disconnected`, `failed`, `closed`.
  void onLiveState(String viewerId, String state);
}

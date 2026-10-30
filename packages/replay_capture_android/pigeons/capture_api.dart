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
    this.recording,
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

  /// Full-session recording; null when the recorder has never been used in this process.
  RecordingStatus? recording;
}

/// Full-session recording (SPEC D8, §3.8): idle, recording, or paused between plays.
enum RecordingState { idle, recording, paused }

class RecordingStatus {
  RecordingStatus({
    required this.state,
    required this.elapsedMs,
    required this.bytes,
    required this.parts,
    required this.freeBytes,
    required this.lowSpace,
    this.remainingMs,
  });

  RecordingState state;

  /// Video time written so far in the current recording, all parts together (pauses excluded).
  int elapsedMs;
  int bytes;

  /// Files of the current recording: a new part starts when the encoder restarts (profile or
  /// thermal change). 0 until the first fragment is written.
  int parts;

  /// Free bytes on shared storage (Movies/InstantReplay).
  int freeBytes;

  /// Estimated recording time left at the current rate before the recorder stops; null if unknown.
  int? remainingMs;

  /// Less than 10 minutes left: warn the coach.
  bool lowSpace;
}

/// Why a recording ended.
enum RecordingEnd { user, lowSpace, error, recovered }

/// A finished recording, now visible in the gallery of the Camera phone.
class RecordingSaved {
  RecordingSaved({
    required this.name,
    required this.parts,
    required this.durationMs,
    required this.bytes,
    required this.reason,
    this.message,
  });

  /// Display name of the first part, e.g. `InstantReplay_2026-10-30_11-30.mp4`.
  String name;
  int parts;
  int durationMs;
  int bytes;
  RecordingEnd reason;

  /// Error detail when [reason] is [RecordingEnd.error].
  String? message;
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

  // Full-session recording (SPEC §3.8). Works only while capture runs, except stop and recover.

  RecordingStatus recordingStatus();

  /// Starts a recording, or resumes a paused one. [includeSeconds] > 0 first writes that much of
  /// the ring buffer (what happened just before pressing). Fails with `no_space` below 1 GB free.
  @async
  RecordingStatus recordStart(int includeSeconds);

  /// Pauses at the end of the fragment in progress.
  @async
  RecordingStatus recordPause();

  /// Finishes the recording and publishes it to the gallery. Null when nothing was recording.
  @async
  RecordingSaved? recordStop();

  /// Finishes recordings left open by a crash or a kill. Call before the first start.
  @async
  List<RecordingSaved> recoverRecordings();
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

  /// The recording state changed (start, pause, resume, new part, low space).
  void onRecording(RecordingStatus status);

  /// A recording finished: by the user, by low space or an error, or recovered after a crash.
  void onRecordingSaved(RecordingSaved saved);
}

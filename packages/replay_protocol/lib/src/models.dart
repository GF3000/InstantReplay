/// JSON data types of API v1. Unknown fields are ignored; optional fields may be absent.
library;

typedef Json = Map<String, Object?>;

/// Outbox lifecycle (SPEC §3.4).
enum ClipState { recording, ready, acked, expired }

class ClipDto {
  const ClipDto({
    required this.id,
    required this.requestId,
    required this.state,
    required this.createdAtMs,
    this.requestedBy,
    this.bytes,
    this.durationMs,
    this.sha256,
  });

  factory ClipDto.fromJson(Json j) => ClipDto(
        id: j['id']! as String,
        requestId: j['requestId']! as String,
        state: ClipState.values.byName(j['state']! as String),
        createdAtMs: j['createdAtMs']! as int,
        requestedBy: j['requestedBy'] as String?,
        bytes: j['bytes'] as int?,
        durationMs: j['durationMs'] as int?,
        sha256: j['sha256'] as String?,
      );

  final String id;
  final String requestId;
  final ClipState state;

  /// Camera wall-clock time of the save request.
  final int createdAtMs;

  /// Viewer that asked for the clip; it downloads and acks it, others may fetch it while ready (D9).
  final String? requestedBy;
  final int? bytes;
  final int? durationMs;
  final String? sha256;

  Json toJson() => {
        'id': id,
        'requestId': requestId,
        'state': state.name,
        'createdAtMs': createdAtMs,
        if (requestedBy != null) 'requestedBy': requestedBy,
        if (bytes != null) 'bytes': bytes,
        if (durationMs != null) 'durationMs': durationMs,
        if (sha256 != null) 'sha256': sha256,
      };

  @override
  bool operator ==(Object other) => other is ClipDto && _eq(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

class CameraInfo {
  const CameraInfo({
    required this.protocolVersion,
    required this.cameraId,
    required this.name,
    this.profileId,
  });

  factory CameraInfo.fromJson(Json j) => CameraInfo(
        protocolVersion: j['protocolVersion']! as int,
        cameraId: j['cameraId']! as String,
        name: j['name']! as String,
        profileId: j['profileId'] as String?,
      );

  final int protocolVersion;
  final String cameraId;
  final String name;

  /// Current capture profile, e.g. `1080p30`; null while not recording.
  final String? profileId;

  Json toJson() => {
        'protocolVersion': protocolVersion,
        'cameraId': cameraId,
        'name': name,
        if (profileId != null) 'profileId': profileId,
      };
}

class PairRequest {
  const PairRequest({required this.code});

  factory PairRequest.fromJson(Json j) => PairRequest(code: j['code']! as String);

  /// The 6-digit code shown on the Camera.
  final String code;

  Json toJson() => {'code': code};
}

class PairResponse {
  const PairResponse({required this.token});

  factory PairResponse.fromJson(Json j) => PairResponse(token: j['token']! as String);

  final String token;

  Json toJson() => {'token': token};
}

class SaveClipRequest {
  const SaveClipRequest({
    required this.requestId,
    required this.preSeconds,
    this.postSeconds = 2,
    this.viewerId,
  });

  factory SaveClipRequest.fromJson(Json j) => SaveClipRequest(
        requestId: j['requestId']! as String,
        preSeconds: (j['preSeconds']! as num).toDouble(),
        postSeconds: (j['postSeconds'] as num?)?.toDouble() ?? 2,
        viewerId: j['viewerId'] as String?,
      );

  /// Client-generated; a retry with the same id never cuts a second clip.
  final String requestId;
  final double preSeconds;
  final double postSeconds;

  /// Becomes [ClipDto.requestedBy]: the viewer that downloads and acks the clip.
  final String? viewerId;

  Json toJson() => {
        'requestId': requestId,
        'preSeconds': preSeconds,
        'postSeconds': postSeconds,
        if (viewerId != null) 'viewerId': viewerId,
      };
}

class AckRequest {
  const AckRequest({required this.sha256});

  factory AckRequest.fromJson(Json j) => AckRequest(sha256: j['sha256']! as String);

  final String sha256;

  Json toJson() => {'sha256': sha256};
}

/// From this `PowerManager.THERMAL_STATUS_*` (MODERATE) the Camera degrades capture, and both roles
/// warn that the phone is hot.
const int hotThermalStatus = 2;

/// Camera status pushed to viewers about once per second.
class CameraStatus {
  const CameraStatus({
    required this.recording,
    required this.fps,
    required this.bufferMs,
    required this.outboxClips,
    required this.thermalStatus,
    this.batteryTempC,
    this.batteryPercent,
    this.plugged,
    this.sessionRecording,
  });

  factory CameraStatus.fromJson(Json j) => CameraStatus(
        recording: j['recording']! as bool,
        fps: (j['fps']! as num).toDouble(),
        bufferMs: j['bufferMs']! as int,
        outboxClips: j['outboxClips']! as int,
        thermalStatus: j['thermalStatus']! as int,
        batteryTempC: (j['batteryTempC'] as num?)?.toDouble(),
        batteryPercent: j['batteryPercent'] as int?,
        plugged: j['plugged'] as bool?,
        sessionRecording: switch (j['sessionRecording']) {
          final Json r => SessionRecording.fromJson(r),
          _ => null,
        },
      );

  /// The capture pipeline is running (the ring buffer is filling). Not the full-session
  /// recording, which is [sessionRecording].
  final bool recording;
  final double fps;
  final int bufferMs;
  final int outboxClips;

  /// PowerManager.THERMAL_STATUS_* (0 none … 6 shutdown).
  final int thermalStatus;
  final double? batteryTempC;
  final int? batteryPercent;
  final bool? plugged;

  /// Full-session recording (SPEC §3.8); null from a Camera without it.
  final SessionRecording? sessionRecording;

  Json toJson() => {
        'recording': recording,
        'fps': fps,
        'bufferMs': bufferMs,
        'outboxClips': outboxClips,
        'thermalStatus': thermalStatus,
        if (batteryTempC != null) 'batteryTempC': batteryTempC,
        if (batteryPercent != null) 'batteryPercent': batteryPercent,
        if (plugged != null) 'plugged': plugged,
        if (sessionRecording != null) 'sessionRecording': sessionRecording!.toJson(),
      };
}

enum SessionRecordingState { idle, recording, paused }

/// Full-session recording on the Camera (SPEC D8, §3.8). Every viewer sees and controls the same one.
class SessionRecording {
  const SessionRecording({
    required this.state,
    required this.elapsedMs,
    required this.parts,
    required this.freeBytes,
    required this.lowSpace,
    this.remainingMs,
  });

  factory SessionRecording.fromJson(Json j) => SessionRecording(
        state: SessionRecordingState.values.asNameMap()[j['state']] ?? SessionRecordingState.idle,
        elapsedMs: j['elapsedMs']! as int,
        parts: j['parts']! as int,
        freeBytes: j['freeBytes']! as int,
        lowSpace: j['lowSpace']! as bool,
        remainingMs: j['remainingMs'] as int?,
      );

  final SessionRecordingState state;

  /// Video time recorded so far, pauses excluded.
  final int elapsedMs;

  /// Files so far: a capture restart (profile or thermal change) starts a new part.
  final int parts;

  /// Free storage on the Camera.
  final int freeBytes;

  /// Estimated recording time left at the current rate; null if unknown.
  final int? remainingMs;

  /// Less than 10 minutes left.
  final bool lowSpace;

  Json toJson() => {
        'state': state.name,
        'elapsedMs': elapsedMs,
        'parts': parts,
        'freeBytes': freeBytes,
        'lowSpace': lowSpace,
        if (remainingMs != null) 'remainingMs': remainingMs,
      };
}

/// Why a full-session recording ended.
enum RecordingEndReason { user, lowSpace, error, recovered }

bool _eq(Json a, Json b) => a.length == b.length && a.keys.every((k) => b.containsKey(k) && a[k] == b[k]);

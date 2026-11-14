/// JSON data types of API v1. Unknown fields are ignored; optional fields may be absent.
library;

import 'broadcast.dart';
import 'youtube.dart';

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
    this.reserved,
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
        reserved: j['reserved'] as bool?,
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

  /// Acknowledged but kept on the Camera in the replay reserve (SPEC §3.4): still downloadable,
  /// and it can go on air (§12.6). `false` when it leaves the reserve (with state `expired`).
  final bool? reserved;

  /// The file is still on the Camera.
  bool get onCamera => state == ClipState.ready || (state == ClipState.acked && reserved == true);

  Json toJson() => {
        'id': id,
        'requestId': requestId,
        'state': state.name,
        'createdAtMs': createdAtMs,
        if (requestedBy != null) 'requestedBy': requestedBy,
        if (bytes != null) 'bytes': bytes,
        if (durationMs != null) 'durationMs': durationMs,
        if (sha256 != null) 'sha256': sha256,
        if (reserved != null) 'reserved': reserved,
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
    this.scoreboard,
    this.broadcast,
    this.zoom,
    this.reserve,
    this.replay,
    this.youtube,
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
        scoreboard: switch (j['scoreboard']) {
          final Json b => ScoreboardState.fromJson(b),
          _ => null,
        },
        broadcast: switch (j['broadcast']) {
          final Json b => BroadcastInfo.fromJson(b),
          _ => null,
        },
        zoom: switch (j['zoom']) {
          final Json z => ZoomInfo.fromJson(z),
          _ => null,
        },
        reserve: switch (j['reserve']) {
          {'size': final int size} => size,
          _ => null,
        },
        replay: switch (j['replay']) {
          final Json r => ReplayInfo.fromJson(r),
          _ => null,
        },
        youtube: switch (j['youtube']) {
          final Json y => YouTubeStatus.fromJson(y),
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

  /// Broadcast mode only (SPEC §12): the scoreboard and the YouTube stream. Absent in replay mode,
  /// and viewers then hide their controls.
  final ScoreboardState? scoreboard;
  final BroadcastInfo? broadcast;

  /// Camera zoom; null from a Camera without it (viewers then hide the zoom controls).
  final ZoomInfo? zoom;

  /// Size of the Camera's replay reserve (SPEC §3.4); null from a Camera without it.
  final int? reserve;

  /// A clip on air instead of the live picture (SPEC §12.6); null otherwise.
  final ReplayInfo? replay;

  /// Broadcast mode only: the Camera's YouTube account and live (SPEC §12.1); null from a Camera
  /// without it (older versions), and viewers then offer only the stream key.
  final YouTubeStatus? youtube;

  /// This status with another [zoom] and [reserve]; every other field kept.
  CameraStatus withControls({ZoomInfo? zoom, int? reserve}) => CameraStatus(
        recording: recording,
        fps: fps,
        bufferMs: bufferMs,
        outboxClips: outboxClips,
        thermalStatus: thermalStatus,
        batteryTempC: batteryTempC,
        batteryPercent: batteryPercent,
        plugged: plugged,
        sessionRecording: sessionRecording,
        scoreboard: scoreboard,
        broadcast: broadcast,
        zoom: zoom,
        reserve: reserve,
        replay: replay,
        youtube: youtube,
      );

  /// This status with another [replay]; every other field kept.
  CameraStatus withReplay(ReplayInfo? replay) => CameraStatus(
        recording: recording,
        fps: fps,
        bufferMs: bufferMs,
        outboxClips: outboxClips,
        thermalStatus: thermalStatus,
        batteryTempC: batteryTempC,
        batteryPercent: batteryPercent,
        plugged: plugged,
        sessionRecording: sessionRecording,
        scoreboard: scoreboard,
        broadcast: broadcast,
        zoom: zoom,
        reserve: reserve,
        replay: replay,
        youtube: youtube,
      );

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
        if (scoreboard != null) 'scoreboard': scoreboard!.toJson(),
        if (broadcast != null) 'broadcast': broadcast!.toJson(),
        if (zoom != null) 'zoom': zoom!.toJson(),
        if (reserve != null) 'reserve': {'size': reserve},
        if (replay != null) 'replay': replay!.toJson(),
        if (youtube != null) 'youtube': youtube!.toJson(),
      };

  /// This status with another [youtube]; every other field kept.
  CameraStatus withYouTube(YouTubeStatus? youtube) => CameraStatus(
        recording: recording,
        fps: fps,
        bufferMs: bufferMs,
        outboxClips: outboxClips,
        thermalStatus: thermalStatus,
        batteryTempC: batteryTempC,
        batteryPercent: batteryPercent,
        plugged: plugged,
        sessionRecording: sessionRecording,
        scoreboard: scoreboard,
        broadcast: broadcast,
        zoom: zoom,
        reserve: reserve,
        replay: replay,
        youtube: youtube,
      );
}

/// A clip on air (SPEC §12.6).
class ReplayInfo {
  const ReplayInfo({required this.clipId, required this.speed, required this.positionMs, required this.durationMs});

  factory ReplayInfo.fromJson(Json j) => ReplayInfo(
        clipId: j['clipId']! as String,
        speed: (j['speed']! as num).toDouble(),
        positionMs: j['positionMs'] as int? ?? 0,
        durationMs: j['durationMs'] as int? ?? 0,
      );

  /// Speeds a replay can run at.
  static const speeds = [0.25, 0.5, 1.0];

  final String clipId;
  final double speed;

  /// Media position in the clip when the status was built.
  final int positionMs;
  final int durationMs;

  Json toJson() => {'clipId': clipId, 'speed': speed, 'positionMs': positionMs, 'durationMs': durationMs};

  @override
  bool operator ==(Object other) =>
      other is ReplayInfo &&
      other.clipId == clipId &&
      other.speed == speed &&
      other.positionMs == positionMs &&
      other.durationMs == durationMs;

  @override
  int get hashCode => Object.hash(clipId, speed, positionMs, durationMs);
}

/// The Camera's sensor zoom (SPEC §3.1): applies to clips, recording and broadcast alike.
class ZoomInfo {
  const ZoomInfo({required this.ratio, required this.max});

  factory ZoomInfo.fromJson(Json j) => ZoomInfo(
        ratio: (j['ratio']! as num).toDouble(),
        max: (j['max']! as num).toDouble(),
      );

  /// Current target, 1…[max].
  final double ratio;

  /// Highest zoom offered (the Camera caps what the sensor allows).
  final double max;

  Json toJson() => {'ratio': ratio, 'max': max};

  @override
  bool operator ==(Object other) => other is ZoomInfo && other.ratio == ratio && other.max == max;

  @override
  int get hashCode => Object.hash(ratio, max);
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

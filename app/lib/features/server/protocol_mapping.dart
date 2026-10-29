import 'package:replay_capture_android/replay_capture_android.dart' as cap;
import 'package:replay_protocol/replay_protocol.dart';

/// Native outbox entry → API v1 clip. [requestedBy] is the viewer that asked for it (D9).
ClipDto clipDto(cap.ClipInfo c, {String? requestedBy}) => ClipDto(
      id: c.id,
      requestId: c.requestId,
      state: ClipState.values.byName(c.state.name),
      createdAtMs: c.createdAtMs,
      requestedBy: requestedBy,
      bytes: c.bytes,
      durationMs: c.durationMs,
      sha256: c.sha256,
    );

/// Native stats → the status pushed to viewers.
CameraStatus cameraStatus(cap.CaptureStats s, {bool recording = true}) => CameraStatus(
      recording: recording,
      fps: s.fps,
      bufferMs: s.bufferMs,
      outboxClips: s.outboxClips,
      thermalStatus: s.thermalStatus,
      batteryTempC: s.batteryTempC,
      batteryPercent: s.batteryPercent,
      plugged: s.plugged,
    );

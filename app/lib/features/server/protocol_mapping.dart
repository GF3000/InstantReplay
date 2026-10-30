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

/// Native stats → the status pushed to viewers. [fallbackRecording] stands in when the stats carry
/// no recording state (the recorder has not been touched yet in this process).
CameraStatus cameraStatus(cap.CaptureStats s, {bool recording = true, cap.RecordingStatus? fallbackRecording}) =>
    CameraStatus(
      recording: recording,
      fps: s.fps,
      bufferMs: s.bufferMs,
      outboxClips: s.outboxClips,
      thermalStatus: s.thermalStatus,
      batteryTempC: s.batteryTempC,
      batteryPercent: s.batteryPercent,
      plugged: s.plugged,
      sessionRecording: switch (s.recording ?? fallbackRecording) {
        final r? => sessionRecording(r),
        null => null,
      },
    );

/// Native recorder state → the full-session recording in the status (SPEC §3.8).
SessionRecording sessionRecording(cap.RecordingStatus r) => SessionRecording(
      state: SessionRecordingState.values.byName(r.state.name),
      elapsedMs: r.elapsedMs,
      parts: r.parts,
      freeBytes: r.freeBytes,
      lowSpace: r.lowSpace,
      remainingMs: r.remainingMs,
    );

/// [status] with another full-session recording; the protocol models have no copyWith.
CameraStatus withSessionRecording(CameraStatus status, SessionRecording? recording) => CameraStatus(
      recording: status.recording,
      fps: status.fps,
      bufferMs: status.bufferMs,
      outboxClips: status.outboxClips,
      thermalStatus: status.thermalStatus,
      batteryTempC: status.batteryTempC,
      batteryPercent: status.batteryPercent,
      plugged: status.plugged,
      sessionRecording: recording,
    );

/// A saved recording → the message every viewer gets.
RecordingFinished recordingFinished(cap.RecordingSaved s) => RecordingFinished(
      name: s.name,
      parts: s.parts,
      durationMs: s.durationMs,
      reason: RecordingEndReason.values.byName(s.reason.name),
    );

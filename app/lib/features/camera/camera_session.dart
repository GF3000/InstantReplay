import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

import '../../core/preferences.dart';
import 'capture_layer.dart';

enum CameraPhase {
  /// Asking for permissions and loading profiles.
  initializing,

  /// The capture pipeline is (re)starting.
  starting,
  running,
  permissionDenied,
  noProfiles,
  startFailed,
}

/// Everything the Camera role screen shows.
@immutable
class CameraSessionState {
  const CameraSessionState({
    this.phase = CameraPhase.initializing,
    this.profiles = const [],
    this.profileId,
    this.session,
    this.stats,
    this.thermalStatus,
    this.cameraState,
    this.errors = const [],
    this.startError,
    this.operating = false,
    this.notificationsDenied = false,
    this.recording,
    this.recovered = const [],
    this.lastSaved,
  });

  final CameraPhase phase;
  final List<CaptureProfile> profiles;
  final String? profileId;

  /// The running capture; null while stopped or starting.
  final StartResult? session;
  final CaptureStats? stats;

  /// Last thermal status from the thermal stream (`PowerManager.THERMAL_STATUS_*`).
  final int? thermalStatus;
  final String? cameraState;

  /// Recent camera errors, newest first. Shown until dismissed.
  final List<String> errors;
  final String? startError;

  /// Operating mode: preview off, black screen with a minimal status line (SPEC §3.5).
  final bool operating;
  final bool notificationsDenied;

  /// Full-session recording (SPEC §3.8); null until the recorder reports, which means idle.
  final RecordingStatus? recording;

  /// Recordings left open by a crash and finished on entry, shown as notes until dismissed.
  final List<RecordingSaved> recovered;

  /// The last recording that ended while this screen was open, for a one-off message.
  final RecordingSavedNotice? lastSaved;

  CaptureProfile? get profile => profiles.where((p) => p.id == profileId).firstOrNull;

  CameraSessionState copyWith({
    CameraPhase? phase,
    List<CaptureProfile>? profiles,
    String? profileId,
    StartResult? Function()? session,
    CaptureStats? Function()? stats,
    int? thermalStatus,
    String? cameraState,
    List<String>? errors,
    String? Function()? startError,
    bool? operating,
    bool? notificationsDenied,
    RecordingStatus? recording,
    List<RecordingSaved>? recovered,
    RecordingSavedNotice? lastSaved,
  }) =>
      CameraSessionState(
        phase: phase ?? this.phase,
        profiles: profiles ?? this.profiles,
        profileId: profileId ?? this.profileId,
        session: session == null ? this.session : session(),
        stats: stats == null ? this.stats : stats(),
        thermalStatus: thermalStatus ?? this.thermalStatus,
        cameraState: cameraState ?? this.cameraState,
        errors: errors ?? this.errors,
        startError: startError == null ? this.startError : startError(),
        operating: operating ?? this.operating,
        notificationsDenied: notificationsDenied ?? this.notificationsDenied,
        recording: recording ?? this.recording,
        recovered: recovered ?? this.recovered,
        lastSaved: lastSaved ?? this.lastSaved,
      );
}

/// Wraps a [RecordingSaved] so that every save is a new value for listeners, even an identical one.
final class RecordingSavedNotice {
  RecordingSavedNotice(this.saved);

  final RecordingSaved saved;
}

/// Owns the capture pipeline while the Camera role screen is open: starts it on entry and stops it
/// when the screen goes away (the provider is auto-disposed).
class CameraSessionNotifier extends Notifier<CameraSessionState> {
  static const defaultProfileId = '1080p30';
  static const _profileKey = 'camera.profile';
  static const _maxErrors = 5;

  late CaptureLayer _capture;
  bool _running = false;

  /// Crash recovery runs once per screen, before the first start (the recorder needs it first).
  bool _recoveryDone = false;

  @override
  CameraSessionState build() {
    _capture = ref.watch(captureLayerProvider);
    final subs = <StreamSubscription<Object>>[
      _capture.stats.listen(
          (s) => state = state.copyWith(stats: () => s, thermalStatus: s.thermalStatus, recording: s.recording)),
      _capture.recording.listen((r) => state = state.copyWith(recording: r)),
      _capture.recordingSaved.listen(_onRecordingSaved),
      _capture.thermal.listen(_onThermal),
      _capture.cameraState.listen((s) => state = state.copyWith(cameraState: s)),
      _capture.errors.listen(_addError),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      // Leaving the Camera finishes the recording first, so it reaches the gallery, then stops
      // capture. Always asked: the recorder may hold a recording this screen has not heard of yet.
      final running = _running;
      _running = false;
      unawaited(() async {
        try {
          await _capture.recordStop();
        } catch (_) {
          // Nothing recording, or the recorder is gone; capture must stop anyway.
        }
        if (running) await _capture.stop().catchError((Object _) {});
      }());
    });
    Future.microtask(enter);
    return const CameraSessionState();
  }

  /// Permissions → profiles → start the default profile. Also the "try again" action.
  Future<void> enter() async {
    state = state.copyWith(phase: CameraPhase.initializing, startError: () => null);
    final bool granted;
    try {
      granted = await _capture.requestCameraPermission();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(phase: CameraPhase.startFailed, startError: () => _describe(e));
      return;
    }
    if (!ref.mounted) return;
    if (!granted) {
      state = state.copyWith(phase: CameraPhase.permissionDenied);
      return;
    }
    final notifications = await _capture.requestNotificationPermission();
    final List<CaptureProfile> profiles;
    try {
      profiles = await _capture.supportedProfiles();
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(phase: CameraPhase.startFailed, startError: () => _describe(e));
      return;
    }
    if (!ref.mounted) return;
    if (profiles.isEmpty) {
      state = state.copyWith(phase: CameraPhase.noProfiles, notificationsDenied: !notifications);
      return;
    }
    // The profile in use (a retry), else the one chosen last time.
    final wanted = state.profileId ?? ref.read(sharedPreferencesProvider).getString(_profileKey);
    final keep = profiles.any((p) => p.id == wanted) ? wanted : null;
    final id = keep ?? (profiles.any((p) => p.id == defaultProfileId) ? defaultProfileId : profiles.first.id);
    state = state.copyWith(profiles: profiles, profileId: id, notificationsDenied: !notifications);
    await _recover();
    if (!ref.mounted) return;
    await _start(id);
  }

  /// Finishes recordings a crash or a kill left open, so they reach the gallery (SPEC §3.8).
  Future<void> _recover() async {
    if (_recoveryDone) return;
    _recoveryDone = true;
    try {
      final found = await _capture.recoverRecordings();
      if (!ref.mounted || found.isEmpty) return;
      final known = {for (final r in state.recovered) r.name};
      state = state.copyWith(recovered: [...state.recovered, ...found.where((r) => !known.contains(r.name))]);
    } catch (e) {
      _addError(_describe(e));
    }
  }

  /// Changing the profile restarts capture. A full-session recording carries on: the recorder
  /// starts a new part with the new encoder.
  Future<void> selectProfile(String id) async {
    if (id == state.profileId && state.phase == CameraPhase.running) return;
    state = state.copyWith(profileId: id);
    unawaited(ref.read(sharedPreferencesProvider).setString(_profileKey, id));
    await _start(id);
  }

  Future<void> _start(String id) async {
    state = state.copyWith(phase: CameraPhase.starting, session: () => null, stats: () => null, startError: () => null);
    try {
      if (_running) {
        _running = false;
        await _capture.stop();
      }
      final session = await _capture.start(id);
      if (!ref.mounted) {
        unawaited(_capture.stop());
        return;
      }
      _running = true;
      state = state.copyWith(phase: CameraPhase.running, session: () => session);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(phase: CameraPhase.startFailed, startError: () => _describe(e));
    }
  }

  Future<void> startOperating() async {
    if (state.operating) return;
    state = state.copyWith(operating: true);
    await _setPreview(false);
  }

  /// When the coach last woke the screen to setup; the automatic switch backs off for a while.
  DateTime? lastWokenAt;

  Future<void> stopOperating() async {
    if (!state.operating) return;
    lastWokenAt = DateTime.now();
    state = state.copyWith(operating: false);
    await _setPreview(true);
  }

  Future<void> _setPreview(bool enabled) async {
    try {
      await _capture.setPreviewEnabled(enabled);
    } catch (e) {
      _addError(_describe(e));
    }
  }

  /// The plugin already turned the preview off, capped or stopped the live view; lowering fps or
  /// resolution needs a restart with another profile (SPEC §3.6).
  void _onThermal(ThermalEvent event) {
    state = state.copyWith(thermalStatus: event.status);
    if (event.action.index >= ThermalAction.previewOff.index && !state.operating) {
      state = state.copyWith(operating: true);
    }
    final current = state.profile;
    final fallback = current == null ? null : thermalFallback(state.profiles, current, event.action);
    if (fallback != null && state.phase == CameraPhase.running) unawaited(selectProfile(fallback.id));
  }

  /// A cooler profile for [action], or null if [current] already satisfies it.
  @visibleForTesting
  static CaptureProfile? thermalFallback(List<CaptureProfile> profiles, CaptureProfile current, ThermalAction action) {
    final candidates = switch (action) {
      ThermalAction.reduceFps => profiles.where((p) => p.fps <= 30 && p.width == current.width),
      ThermalAction.reduceResolution || ThermalAction.stopLive => profiles.where((p) => p.fps <= 30),
      _ => const <CaptureProfile>[],
    };
    final cooler = candidates.where((p) => p.width * p.height * p.fps < current.width * current.height * current.fps);
    if (cooler.isEmpty) return null;
    // The best of the cooler options (profiles are ordered best first).
    return action == ThermalAction.reduceFps
        ? cooler.first
        : cooler.reduce((a, b) => a.width * a.height <= b.width * b.height ? a : b);
  }

  // region Full-session recording (SPEC §3.8). Errors are rethrown for the screen to show.

  /// Starts, or resumes when paused. [includeSeconds] > 0 also keeps that much of the buffer.
  Future<void> recordStart({int includeSeconds = 0}) async {
    final status = await _capture.recordStart(includeSeconds: includeSeconds);
    if (ref.mounted) state = state.copyWith(recording: status);
  }

  Future<void> recordPause() async {
    final status = await _capture.recordPause();
    if (ref.mounted) state = state.copyWith(recording: status);
  }

  /// Finishes and saves to the gallery; the saved event brings the message.
  Future<void> recordStop() async {
    await _capture.recordStop();
    if (!ref.mounted) return;
    state = state.copyWith(recording: await _capture.recordingStatus());
  }

  void _onRecordingSaved(RecordingSaved saved) {
    if (!ref.mounted) return;
    if (saved.reason == RecordingEnd.recovered) {
      // Also returned by recoverRecordings(); keep one note per file.
      if (state.recovered.any((r) => r.name == saved.name)) return;
      state = state.copyWith(recovered: [...state.recovered, saved]);
      return;
    }
    state = state.copyWith(lastSaved: RecordingSavedNotice(saved));
  }

  void dismissRecovered() => state = state.copyWith(recovered: const []);

  // endregion

  void dismissErrors() => state = state.copyWith(errors: const []);

  /// Debug helper until the Viewer can request clips.
  Future<ClipInfo> saveTestClip() =>
      _capture.saveClip(requestId: 'camera-test-${DateTime.now().microsecondsSinceEpoch}', preSeconds: 20);

  void _addError(String message) {
    if (!ref.mounted) return;
    state = state.copyWith(errors: [message, ...state.errors].take(_maxErrors).toList());
  }

  static String _describe(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';
}

final cameraSessionProvider =
    NotifierProvider.autoDispose<CameraSessionNotifier, CameraSessionState>(CameraSessionNotifier.new);

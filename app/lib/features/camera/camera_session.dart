import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

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
      );
}

/// Owns the capture pipeline while the Camera role screen is open: starts it on entry and stops it
/// when the screen goes away (the provider is auto-disposed).
class CameraSessionNotifier extends Notifier<CameraSessionState> {
  static const defaultProfileId = '1080p30';
  static const _maxErrors = 5;

  late CaptureLayer _capture;
  bool _running = false;

  @override
  CameraSessionState build() {
    _capture = ref.watch(captureLayerProvider);
    final subs = <StreamSubscription<Object>>[
      _capture.stats.listen((s) => state = state.copyWith(stats: () => s, thermalStatus: s.thermalStatus)),
      _capture.thermal.listen((t) => state = state.copyWith(thermalStatus: t.status)),
      _capture.cameraState.listen((s) => state = state.copyWith(cameraState: s)),
      _capture.errors.listen(_addError),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      if (_running) {
        _running = false;
        unawaited(_capture.stop().catchError((Object _) {}));
      }
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
    final keep = profiles.any((p) => p.id == state.profileId) ? state.profileId : null;
    final id = keep ?? (profiles.any((p) => p.id == defaultProfileId) ? defaultProfileId : profiles.first.id);
    state = state.copyWith(profiles: profiles, profileId: id, notificationsDenied: !notifications);
    await _start(id);
  }

  /// Changing the profile restarts capture.
  Future<void> selectProfile(String id) async {
    if (id == state.profileId && state.phase == CameraPhase.running) return;
    state = state.copyWith(profileId: id);
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

  Future<void> stopOperating() async {
    if (!state.operating) return;
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

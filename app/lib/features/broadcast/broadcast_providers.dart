import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../core/preferences.dart';
import '../../l10n/app_localizations.dart';
import '../camera/camera_session.dart';
import '../camera/capture_layer.dart';
import '../settings/settings_providers.dart';
import 'broadcast_controller.dart';
import 'broadcast_host.dart';
import 'replay_controller.dart';
import 'scoreboard_controller.dart';

// Broadcast mode on the Camera (SPEC §12): the scoreboard and the stream live as long as the
// Camera screen, and the API server reaches them through [broadcastHostProvider].

/// Monotonic milliseconds for the scoreboard clock; tests override it.
final monotonicClockProvider = Provider<int Function()>((ref) {
  final watch = Stopwatch()..start();
  return () => watch.elapsedMilliseconds;
});

/// The app's language (the Settings choice, else the system's) for the period label on air.
final cameraL10nProvider = Provider<AppLocalizations Function()>((ref) => () {
      final wanted = ref.read(localeProvider) ?? PlatformDispatcher.instance.locale;
      final supported = AppLocalizations.supportedLocales.any((l) => l.languageCode == wanted.languageCode);
      return lookupAppLocalizations(Locale(supported ? wanted.languageCode : 'en'));
    });

final scoreboardControllerProvider = Provider.autoDispose<ScoreboardController>((ref) {
  final capture = ref.watch(captureLayerProvider);
  final controller = ScoreboardController(
    prefs: ref.watch(sharedPreferencesProvider),
    clockMs: ref.watch(monotonicClockProvider),
    setOverlay: capture.setOverlay,
    l10n: ref.watch(cameraL10nProvider),
  );
  // The overlay goes out whenever capture (re)starts in broadcast mode: the plugin starts blank.
  ref.listen(cameraSessionProvider.select((s) => (s.broadcast && s.phase == CameraPhase.running, s.session)),
      (_, next) => controller.overlayEnabled = next.$1,
      fireImmediately: true);
  ref.listen(localeProvider, (_, _) => controller.pushOverlay());
  ref.onDispose(controller.dispose);
  return controller;
});

/// The scoreboard for the Camera screen, on every change.
final scoreboardStateProvider = StreamProvider.autoDispose<ScoreboardState>((ref) async* {
  final controller = ref.watch(scoreboardControllerProvider);
  yield controller.current;
  yield* controller.changes;
});

final broadcastControllerProvider = Provider.autoDispose<BroadcastController>((ref) {
  final controller = BroadcastController(
    prefs: ref.watch(sharedPreferencesProvider),
    capture: ref.watch(captureLayerProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// The stream for the Camera screen, on every change (bitrate and uptime included).
final broadcastInfoProvider = StreamProvider.autoDispose<BroadcastInfo>((ref) async* {
  final controller = ref.watch(broadcastControllerProvider);
  yield controller.info;
  yield* controller.changes;
});

/// Replays on air (SPEC §12.6); only while the stream is active.
final replayControllerProvider = Provider.autoDispose<ReplayController>((ref) {
  final stream = ref.watch(broadcastControllerProvider);
  final controller = ReplayController(
    capture: ref.watch(captureLayerProvider),
    clockMs: ref.watch(monotonicClockProvider),
    l10n: ref.watch(cameraL10nProvider),
    isLive: () => stream.info.active,
    replayScoreboard: () => stream.replayScoreboard,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// The replay on air for the Camera screen (its position when it started, changed speed or
/// ended); null while the program shows the camera.
final replayInfoProvider = StreamProvider.autoDispose<ReplayInfo?>((ref) async* {
  final controller = ref.watch(replayControllerProvider);
  yield controller.current;
  yield* controller.changes.map((_) => controller.current);
});

/// What the API server sees of broadcast mode.
final broadcastHostProvider = Provider.autoDispose<BroadcastHost>((ref) {
  final scoreboard = ref.watch(scoreboardControllerProvider);
  final stream = ref.watch(broadcastControllerProvider);
  final replay = ref.watch(replayControllerProvider);
  final changes = StreamController<void>.broadcast();
  final subs = [
    scoreboard.changes.listen((_) => changes.add(null)),
    stream.stateChanges.listen((_) => changes.add(null)),
    replay.changes.listen((_) => changes.add(null)),
  ];
  ref.listen(cameraSessionProvider.select((s) => s.broadcast), (_, _) => changes.add(null));
  ref.onDispose(() {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    unawaited(changes.close());
  });
  return CameraBroadcast(
    scoreboard: scoreboard,
    stream: stream,
    replay: replay,
    isActive: () => ref.read(cameraSessionProvider).broadcast,
    changes: changes.stream,
  );
});

/// [BroadcastHost] over the scoreboard, stream and replay controllers.
class CameraBroadcast implements BroadcastHost {
  CameraBroadcast({
    required this._scoreboard,
    required this._stream,
    required this._replay,
    required this._isActive,
    required this.changes,
  });

  final ScoreboardController _scoreboard;
  final BroadcastController _stream;
  final ReplayController _replay;
  final bool Function() _isActive;

  @override
  final Stream<void> changes;

  @override
  bool get active => _isActive();

  @override
  ScoreboardState get scoreboard => _scoreboard.current;

  @override
  BroadcastInfo get info => _stream.info;

  @override
  void scoreboardCommand(ScoreboardCommand command) => _scoreboard.apply(command);

  @override
  ValueListenable<double?> get micLevel => _stream.micLevel;

  @override
  Future<void> configure({
    required String server,
    String? key,
    required int targetKbps,
    required bool audio,
    bool? replayScoreboard,
  }) =>
      _stream.configure(
        server: server,
        key: key,
        targetKbps: targetKbps,
        audio: audio,
        replayScoreboard: replayScoreboard,
      );

  @override
  Future<bool> start() => _stream.start();

  @override
  Future<void> stop() => _stream.stop();

  @override
  ReplayInfo? get replay => _replay.current;

  @override
  Stream<String> get replayFailures => _replay.failures;

  @override
  Future<void> replayAir(String clipId, double speed) => _replay.air(clipId, speed: speed);

  @override
  Future<void> replaySpeed(double speed) => _replay.setSpeed(speed);

  @override
  Future<void> replayStop() => _replay.stop();
}

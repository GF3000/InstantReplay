import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:replay_capture_android/replay_capture_android.dart' show ReplayStatus;
import 'package:replay_protocol/replay_protocol.dart';

import '../../l10n/app_localizations.dart';
import '../camera/capture_layer.dart';
import 'broadcast_host.dart';

/// Replays on air on the Camera (SPEC §12.6): puts a clip on the stream instead of the live
/// picture, changes its speed, cuts back to live, and keeps the replay on air as the plugin
/// reports it.
class ReplayController {
  ReplayController({
    required this.capture,
    required this._clockMs,
    required this._l10n,
    required this._isLive,
    bool Function()? replayScoreboard,
  }) : _replayScoreboard = replayScoreboard ?? _never {
    _subs
      ..add(capture.replay.listen(_onReplay))
      ..add(capture.replayEnded.listen(_onEnded))
      ..add(capture.stats.listen((s) => _onStats(s.replay)));
  }

  /// Error codes the plugin uses that go to viewers as they are.
  static const errorCodes = {'not_live', 'replay_unavailable', 'replay_failed'};

  /// A replay the stats stopped reporting is taken as ended after this long without news of it
  /// (in case the end event was lost).
  static const staleMs = 2500;

  final CaptureLayer capture;
  final int Function() _clockMs;
  final AppLocalizations Function() _l10n;

  /// The stream is starting, on air or reconnecting.
  final bool Function() _isLive;

  /// The stream setting "scoreboard during replays" (SPEC §12.6), read at each start.
  final bool Function() _replayScoreboard;

  static bool _never() => false;

  final _subs = <StreamSubscription<Object?>>[];
  final _changes = StreamController<void>.broadcast();
  final _failures = StreamController<String>.broadcast();

  ReplayInfo? _status;

  /// Monotonic time when [_status]'s position was read.
  int _anchorMs = 0;

  /// Last time the plugin said this replay is on air.
  int _confirmedMs = 0;

  /// Starts in flight: end events meanwhile belong to the replay being replaced.
  int _starting = 0;

  /// The replay on air, its position as of now; null while the program shows the camera.
  ReplayInfo? get current {
    final s = _status;
    if (s == null) return null;
    final elapsed = _clockMs() - _anchorMs;
    var position = s.positionMs + (elapsed * s.speed).round();
    if (s.durationMs > 0) position = position.clamp(0, s.durationMs);
    return ReplayInfo(clipId: s.clipId, speed: s.speed, positionMs: position, durationMs: s.durationMs);
  }

  /// A replay went on air, changed speed or ended.
  Stream<void> get changes => _changes.stream;

  /// A replay that failed on air, with the plugin's reason.
  Stream<String> get failures => _failures.stream;

  /// Puts [clipId] on air at [speed] (the nearest of [ReplayInfo.speeds]), replacing any replay
  /// on air. Throws [BroadcastException] `not_live`, `replay_unavailable` or `replay_failed`.
  Future<void> air(String clipId, {double speed = 1}) async {
    if (!_isLive()) throw const BroadcastException('not_live');
    _starting++;
    try {
      final status = await capture.replayStart(
        clipId,
        speed: nearestSpeed(speed),
        label: _l10n().replayLabelOnAir,
        scoreboard: _replayScoreboard(),
      );
      final next = _info(status);
      _set(next, emit: _isNews(current, next)); // The plugin's event may have said it already.
    } on PlatformException catch (e) {
      throw BroadcastException(errorCodes.contains(e.code) ? e.code : 'replay_failed', e.message ?? e.code);
    } finally {
      _starting--;
    }
  }

  /// Changes the speed of the replay on air (the nearest of [ReplayInfo.speeds]); nothing without
  /// one.
  Future<void> setSpeed(double speed) async {
    final now = current;
    if (now == null) return;
    final s = nearestSpeed(speed);
    try {
      await capture.replaySpeed(s);
    } on PlatformException catch (e) {
      throw BroadcastException('replay_failed', e.message ?? e.code);
    }
    // The plugin's event normally beats this; the position stays where it was.
    final after = current;
    if (after != null && after.clipId == now.clipId && after.speed != s) {
      _set(ReplayInfo(clipId: after.clipId, speed: s, positionMs: after.positionMs, durationMs: after.durationMs));
    }
  }

  /// Back to the live picture; nothing without a replay on air.
  Future<void> stop() async {
    final clipId = _status?.clipId;
    if (clipId == null) return;
    try {
      await capture.replayStop();
    } on PlatformException catch (e) {
      throw BroadcastException('replay_failed', e.message ?? e.code);
    }
    if (_status?.clipId == clipId) _clear();
  }

  void _onReplay(ReplayStatus status) {
    final next = _info(status);
    _set(next, emit: _isNews(current, next));
  }

  /// Another clip, another speed, or the same clip started again: viewers must hear at once.
  /// Otherwise only the position moved, which the stats carry.
  static bool _isNews(ReplayInfo? before, ReplayInfo next) =>
      before == null ||
      before.clipId != next.clipId ||
      before.speed != next.speed ||
      next.positionMs + 500 < before.positionMs;

  void _onEnded(({String clipId, String? error}) ended) {
    if (_starting > 0 || ended.clipId != _status?.clipId) return; // The replay being replaced.
    _clear();
    if (ended.error case final error? when !_failures.isClosed) _failures.add(error);
  }

  void _onStats(ReplayStatus? r) {
    final s = _status;
    if (r == null) {
      if (s != null && _starting == 0 && _clockMs() - _confirmedMs > staleMs) _clear();
      return;
    }
    if (s == null || r.clipId != s.clipId || r.speed != s.speed) {
      if (_starting == 0) _set(_info(r));
      return;
    }
    _set(_info(r), emit: false); // Only the position moved: re-anchor it.
  }

  static ReplayInfo _info(ReplayStatus s) =>
      ReplayInfo(clipId: s.clipId, speed: s.speed, positionMs: s.positionMs, durationMs: s.durationMs);

  void _set(ReplayInfo info, {bool emit = true}) {
    _status = info;
    _anchorMs = _confirmedMs = _clockMs();
    if (emit && !_changes.isClosed) _changes.add(null);
  }

  void _clear() {
    if (_status == null) return;
    _status = null;
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_changes.close());
    unawaited(_failures.close());
  }

  /// The one of [ReplayInfo.speeds] closest to [speed].
  static double nearestSpeed(double speed) {
    if (speed.isNaN) return 1;
    var best = ReplayInfo.speeds.first;
    for (final s in ReplayInfo.speeds) {
      if ((s - speed).abs() < (best - speed).abs()) best = s;
    }
    return best;
  }
}

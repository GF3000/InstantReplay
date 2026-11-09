import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show OverlayState;
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

/// The scoreboard on the Camera (SPEC §12.2): the one true state, its clock, its persistence and
/// the overlay the native side burns into the stream. Viewers change it through commands.
///
/// [state] is anchored at a monotonic instant; reading [current] advances a running clock to now.
/// Every command re-anchors, is saved to preferences and pushes a new overlay.
class ScoreboardController {
  ScoreboardController({
    required this._prefs,
    required int Function() clockMs,
    required this.setOverlay,
    required this._l10n,
    this.saveEvery = const Duration(seconds: 10),
  }) : _clock = clockMs {
    _state = load(_prefs);
    _anchor = _clock();
  }

  static const storageKey = 'broadcast.scoreboard';

  final SharedPreferences _prefs;
  final int Function() _clock;
  final AppLocalizations Function() _l10n;

  /// Draws the overlay (the capture plugin); only called while [overlayEnabled].
  final Future<void> Function(OverlayState overlay) setOverlay;

  /// How often a running clock is saved, so a crash loses at most this much of it.
  final Duration saveEvery;

  final _changes = StreamController<ScoreboardState>.broadcast();
  late ScoreboardState _state;
  late int _anchor;
  Timer? _saver;
  bool _overlayEnabled = false;

  /// The state at its anchor; see [current] for the clock now.
  @visibleForTesting
  ScoreboardState get state => _state;

  /// The scoreboard now: a running clock is advanced to this moment.
  ScoreboardState get current => anchoredAt(_state, _clock() - _anchor);

  /// Every change, as [current] at that moment.
  Stream<ScoreboardState> get changes => _changes.stream;

  /// Capture runs in broadcast mode, so the plugin accepts overlays. Turning it on pushes the
  /// current one (capture just started).
  bool get overlayEnabled => _overlayEnabled;

  set overlayEnabled(bool enabled) {
    _overlayEnabled = enabled;
    if (enabled) pushOverlay();
  }

  void apply(ScoreboardCommand command) {
    final now = _clock();
    _state = _state.apply(command, elapsedMs: now - _anchor);
    _anchor = now;
    _save();
    _saver?.cancel();
    _saver = _state.clockRunning ? Timer.periodic(saveEvery, (_) => _save()) : null;
    pushOverlay();
    if (!_changes.isClosed) _changes.add(_state);
  }

  /// Sends what the overlay shows now (also after a language change).
  void pushOverlay() {
    if (!_overlayEnabled) return;
    unawaited(setOverlay(overlayFor(current, _l10n())).catchError((Object e) {
      debugPrint('setOverlay failed: $e');
    }));
  }

  void dispose() {
    _saver?.cancel();
    _save();
    unawaited(_changes.close());
  }

  void _save() => unawaited(_prefs.setString(storageKey, jsonEncode(current.toJson())));

  /// The saved scoreboard, or a fresh one. A clock that was running comes back paused at its last
  /// saved value.
  static ScoreboardState load(SharedPreferences prefs) {
    final raw = prefs.getString(storageKey);
    if (raw == null) return ScoreboardState.initial;
    try {
      final saved = ScoreboardState.fromJson(jsonDecode(raw) as Json);
      return rebuild(saved, clockMs: saved.clockMs, running: false);
    } catch (_) {
      return ScoreboardState.initial;
    }
  }
}

/// [s] advanced by [elapsedMs] and re-anchored there.
ScoreboardState anchoredAt(ScoreboardState s, int elapsedMs) {
  if (!s.clockRunning) return s;
  final ms = s.clockAt(elapsedMs);
  return rebuild(s, clockMs: ms, running: !(s.countDown && ms == 0));
}

/// [s] with another clock value and running flag; the protocol model keeps its copy private.
ScoreboardState rebuild(ScoreboardState s, {required int clockMs, required bool running}) => ScoreboardState(
      home: s.home,
      away: s.away,
      period: s.period,
      periods: s.periods,
      periodMs: s.periodMs,
      countDown: s.countDown,
      clockMs: clockMs,
      clockRunning: running,
      visible: s.visible,
    );

/// The period as shown on air: `1T`/`2T` (es) or `1H`/`2H` (en) for halves, `P1`… for thirds,
/// `Q1`… for quarters, nothing for a single period.
String periodLabel(AppLocalizations l10n, {required int period, required int periods}) => switch (periods) {
      2 => l10n.scoreboardHalf(period),
      3 => 'P$period',
      4 => 'Q$period',
      _ => '',
    };

/// The native overlay for [s].
OverlayState overlayFor(ScoreboardState s, AppLocalizations l10n) => OverlayState(
      visible: s.visible,
      homeName: s.home.name.toUpperCase(),
      awayName: s.away.name.toUpperCase(),
      homeScore: s.home.score,
      awayScore: s.away.score,
      homeColor: s.home.color,
      awayColor: s.away.color,
      periodLabel: periodLabel(l10n, period: s.period, periods: s.periods),
      clockMs: s.clockMs,
      clockRunning: s.clockRunning,
      countDown: s.countDown,
    );

/// Broadcast mode (SPEC §12): the scoreboard the Camera burns into its YouTube stream, the
/// commands viewers send to change it, and the state of the stream itself.
library;

import 'models.dart';

enum Team { home, away }

class TeamState {
  const TeamState({required this.name, this.score = 0, required this.color});

  factory TeamState.fromJson(Json j) => TeamState(
        name: j['name']! as String,
        score: j['score'] as int? ?? 0,
        color: j['color']! as int,
      );

  /// 1–5 characters, shown upper-case on air.
  final String name;
  final int score;

  /// ARGB.
  final int color;

  TeamState copyWith({String? name, int? score, int? color}) =>
      TeamState(name: name ?? this.name, score: score ?? this.score, color: color ?? this.color);

  Json toJson() => {'name': name, 'score': score, 'color': color};

  @override
  bool operator ==(Object other) =>
      other is TeamState && other.name == name && other.score == score && other.color == color;

  @override
  int get hashCode => Object.hash(name, score, color);
}

/// What a viewer can configure; scores, period and clock are changed by commands.
class ScoreboardSettings {
  const ScoreboardSettings({
    required this.homeName,
    required this.awayName,
    required this.homeColor,
    required this.awayColor,
    required this.periods,
    required this.periodMs,
    required this.countDown,
    this.scale = ScoreboardState.defaultScale,
  });

  factory ScoreboardSettings.fromJson(Json j) => ScoreboardSettings(
        homeName: j['homeName']! as String,
        awayName: j['awayName']! as String,
        homeColor: j['homeColor']! as int,
        awayColor: j['awayColor']! as int,
        periods: j['periods']! as int,
        periodMs: j['periodMs']! as int,
        countDown: j['countDown']! as bool,
        scale: j['scale'] as int? ?? ScoreboardState.defaultScale,
      );

  final String homeName;
  final String awayName;
  final int homeColor;
  final int awayColor;

  /// 1–4.
  final int periods;
  final int periodMs;
  final bool countDown;

  /// Overlay size in percent of the base bar (SPEC §12.2).
  final int scale;

  Json toJson() => {
        'homeName': homeName,
        'awayName': awayName,
        'homeColor': homeColor,
        'awayColor': awayColor,
        'periods': periods,
        'periodMs': periodMs,
        'countDown': countDown,
        'scale': scale,
      };
}

/// The scoreboard (SPEC §12.2). [clockMs] is the clock value at the moment this state was built
/// (its anchor); while [clockRunning], use [clockAt] with the time elapsed since then.
class ScoreboardState {
  const ScoreboardState({
    required this.home,
    required this.away,
    this.period = 1,
    this.periods = 2,
    this.periodMs = 45 * 60 * 1000,
    this.countDown = false,
    this.clockMs = 0,
    this.clockRunning = false,
    this.visible = true,
    this.scale = defaultScale,
  });

  factory ScoreboardState.fromJson(Json j) {
    final clock = j['clock'] as Json? ?? const {};
    return ScoreboardState(
      home: TeamState.fromJson(j['home']! as Json),
      away: TeamState.fromJson(j['away']! as Json),
      period: j['period'] as int? ?? 1,
      periods: j['periods'] as int? ?? 2,
      periodMs: j['periodMs'] as int? ?? 45 * 60 * 1000,
      countDown: j['countDown'] as bool? ?? false,
      clockMs: clock['ms'] as int? ?? 0,
      clockRunning: clock['running'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
      scale: j['scale'] as int? ?? defaultScale,
    );
  }

  /// A fresh football-style board: two halves of 45 min counting up.
  static const initial = ScoreboardState(
    home: TeamState(name: 'LOC', color: 0xFF1E88E5),
    away: TeamState(name: 'VIS', color: 0xFFE53935),
  );

  static const maxNameLength = 5;
  static const maxPeriods = 4;

  /// Overlay sizes offered to viewers, in percent of the base bar (56 px high at 1080p).
  static const scales = [100, 130, 160];
  static const defaultScale = 130;

  final TeamState home;
  final TeamState away;

  /// 1-based.
  final int period;
  final int periods;
  final int periodMs;
  final bool countDown;
  final int clockMs;
  final bool clockRunning;
  final bool visible;

  /// Overlay size in percent of the base bar.
  final int scale;

  TeamState team(Team t) => t == Team.home ? home : away;

  /// Clock value [elapsedMs] after this state's anchor. A count-down clock stops at 0.
  int clockAt(int elapsedMs) {
    if (!clockRunning) return clockMs;
    return countDown ? (clockMs - elapsedMs).clamp(0, clockMs) : clockMs + elapsedMs;
  }

  /// Clock value at the start of a period.
  int get periodStartMs => countDown ? periodMs : 0;

  /// The state after [command], re-anchored [elapsedMs] after this state's anchor (the caller
  /// takes "now" as the new anchor). Invalid values are clamped rather than rejected.
  ScoreboardState apply(ScoreboardCommand command, {required int elapsedMs}) {
    // Re-anchor first, so every result has clockMs = the value now.
    final now = clockAt(elapsedMs);
    final running = clockRunning && !(countDown && now == 0);
    final base = _copy(clockMs: now, clockRunning: running);
    return switch (command) {
      ScoreCommand(:final team, :final delta) => team == Team.home
          ? base._copy(home: home.copyWith(score: (home.score + delta).clamp(0, 999)))
          : base._copy(away: away.copyWith(score: (away.score + delta).clamp(0, 999))),
      ClockStartCommand() => base._copy(clockRunning: !(countDown && now == 0)),
      ClockPauseCommand() => base._copy(clockRunning: false),
      ClockSetCommand(:final ms) => base._copy(clockMs: ms.clamp(0, 24 * 60 * 60 * 1000)),
      PeriodCommand(:final delta) => base._copy(
          period: (period + delta).clamp(1, periods),
          clockMs: periodStartMs,
          clockRunning: false,
        ),
      SettingsCommand(:final settings) => _withSettings(base, settings),
      VisibleCommand(:final visible) => base._copy(visible: visible),
      ResetCommand() => base._copy(
          home: home.copyWith(score: 0),
          away: away.copyWith(score: 0),
          period: 1,
          clockMs: periodStartMs,
          clockRunning: false,
        ),
    };
  }

  static ScoreboardState _withSettings(ScoreboardState base, ScoreboardSettings s) {
    final periods = s.periods.clamp(1, maxPeriods);
    final periodMs = s.periodMs.clamp(60 * 1000, 120 * 60 * 1000);
    final clockChanged = s.countDown != base.countDown || periodMs != base.periodMs;
    final next = base._copy(
      home: base.home.copyWith(name: normalizeName(s.homeName, base.home.name), color: s.homeColor),
      away: base.away.copyWith(name: normalizeName(s.awayName, base.away.name), color: s.awayColor),
      periods: periods,
      period: base.period.clamp(1, periods),
      periodMs: periodMs,
      countDown: s.countDown,
      scale: s.scale.clamp(50, 250),
    );
    // A new clock mode or length restarts the period clock, paused.
    return clockChanged ? next._copy(clockMs: next.periodStartMs, clockRunning: false) : next;
  }

  /// Upper-case, trimmed, at most [maxNameLength] characters; [fallback] when empty.
  static String normalizeName(String name, String fallback) {
    final n = name.trim().toUpperCase();
    if (n.isEmpty) return fallback;
    return n.length > maxNameLength ? n.substring(0, maxNameLength) : n;
  }

  ScoreboardSettings get settings => ScoreboardSettings(
        homeName: home.name,
        awayName: away.name,
        homeColor: home.color,
        awayColor: away.color,
        periods: periods,
        periodMs: periodMs,
        countDown: countDown,
        scale: scale,
      );

  ScoreboardState _copy({
    TeamState? home,
    TeamState? away,
    int? period,
    int? periods,
    int? periodMs,
    bool? countDown,
    int? clockMs,
    bool? clockRunning,
    bool? visible,
    int? scale,
  }) =>
      ScoreboardState(
        home: home ?? this.home,
        away: away ?? this.away,
        period: period ?? this.period,
        periods: periods ?? this.periods,
        periodMs: periodMs ?? this.periodMs,
        countDown: countDown ?? this.countDown,
        clockMs: clockMs ?? this.clockMs,
        clockRunning: clockRunning ?? this.clockRunning,
        visible: visible ?? this.visible,
        scale: scale ?? this.scale,
      );

  Json toJson() => {
        'home': home.toJson(),
        'away': away.toJson(),
        'period': period,
        'periods': periods,
        'periodMs': periodMs,
        'countDown': countDown,
        'clock': {'ms': clockMs, 'running': clockRunning},
        'visible': visible,
        'scale': scale,
      };

  @override
  bool operator ==(Object other) =>
      other is ScoreboardState &&
      other.home == home &&
      other.away == away &&
      other.period == period &&
      other.periods == periods &&
      other.periodMs == periodMs &&
      other.countDown == countDown &&
      other.clockMs == clockMs &&
      other.clockRunning == clockRunning &&
      other.visible == visible &&
      other.scale == scale;

  @override
  int get hashCode =>
      Object.hash(home, away, period, periods, periodMs, countDown, clockMs, clockRunning, visible, scale);
}

/// `mm:ss`, minutes not capped (e.g. `93:12` in added time).
String formatClock(int ms) {
  final total = ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// A change to the scoreboard sent by a viewer (`scoreboard_cmd`, SPEC §12.3).
sealed class ScoreboardCommand {
  const ScoreboardCommand();

  String get action;

  Json fields();

  Json toJson() => {'action': action, ...fields()};

  /// Null for unknown actions or missing fields.
  static ScoreboardCommand? fromJson(Json j) {
    try {
      return switch (j['action']) {
        ScoreCommand.name => ScoreCommand(
            team: Team.values.byName(j['team']! as String),
            delta: (j['delta']! as int).clamp(-1, 1),
          ),
        ClockStartCommand.name => const ClockStartCommand(),
        ClockPauseCommand.name => const ClockPauseCommand(),
        ClockSetCommand.name => ClockSetCommand(ms: j['ms']! as int),
        PeriodCommand.name => PeriodCommand(delta: (j['delta']! as int).clamp(-1, 1)),
        SettingsCommand.name => SettingsCommand(ScoreboardSettings.fromJson(j['settings']! as Json)),
        VisibleCommand.name => VisibleCommand(visible: j['visible']! as bool),
        ResetCommand.name => const ResetCommand(),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

final class ScoreCommand extends ScoreboardCommand {
  const ScoreCommand({required this.team, required this.delta});

  static const name = 'score';
  final Team team;

  /// +1 or -1.
  final int delta;

  @override
  String get action => name;

  @override
  Json fields() => {'team': team.name, 'delta': delta};
}

final class ClockStartCommand extends ScoreboardCommand {
  const ClockStartCommand();

  static const name = 'clock_start';

  @override
  String get action => name;

  @override
  Json fields() => const {};
}

final class ClockPauseCommand extends ScoreboardCommand {
  const ClockPauseCommand();

  static const name = 'clock_pause';

  @override
  String get action => name;

  @override
  Json fields() => const {};
}

final class ClockSetCommand extends ScoreboardCommand {
  const ClockSetCommand({required this.ms});

  static const name = 'clock_set';
  final int ms;

  @override
  String get action => name;

  @override
  Json fields() => {'ms': ms};
}

final class PeriodCommand extends ScoreboardCommand {
  const PeriodCommand({required this.delta});

  static const name = 'period';
  final int delta;

  @override
  String get action => name;

  @override
  Json fields() => {'delta': delta};
}

final class SettingsCommand extends ScoreboardCommand {
  const SettingsCommand(this.settings);

  static const name = 'settings';
  final ScoreboardSettings settings;

  @override
  String get action => name;

  @override
  Json fields() => {'settings': settings.toJson()};
}

final class VisibleCommand extends ScoreboardCommand {
  const VisibleCommand({required this.visible});

  static const name = 'visible';
  final bool visible;

  @override
  String get action => name;

  @override
  Json fields() => {'visible': visible};
}

final class ResetCommand extends ScoreboardCommand {
  const ResetCommand();

  static const name = 'reset';

  @override
  String get action => name;

  @override
  Json fields() => const {};
}

enum BroadcastStreamState { idle, connecting, live, reconnecting, failed }

/// The YouTube stream as viewers see it (`status.broadcast`). Never carries the stream key.
class BroadcastInfo {
  const BroadcastInfo({
    required this.state,
    required this.configured,
    required this.server,
    required this.targetKbps,
    required this.audio,
    this.keyHint,
    this.bitrateKbps,
    this.uptimeMs,
    this.message,
  });

  factory BroadcastInfo.fromJson(Json j) => BroadcastInfo(
        state: BroadcastStreamState.values.asNameMap()[j['state']] ?? BroadcastStreamState.idle,
        configured: j['configured'] as bool? ?? false,
        server: j['server'] as String? ?? defaultServer,
        targetKbps: j['targetKbps'] as int? ?? defaultKbps,
        audio: j['audio'] as bool? ?? true,
        keyHint: j['keyHint'] as String?,
        bitrateKbps: j['bitrateKbps'] as int?,
        uptimeMs: j['uptimeMs'] as int?,
        message: j['message'] as String?,
      );

  static const defaultServer = 'rtmp://a.rtmp.youtube.com/live2';
  static const defaultKbps = 4500;
  static const minKbps = 2500;
  static const maxKbps = 6000;

  final BroadcastStreamState state;

  /// A stream key is stored on the Camera.
  final bool configured;
  final String server;

  /// Last 4 characters of the stored key.
  final String? keyHint;

  /// Configured video target.
  final int targetKbps;
  final bool audio;

  /// Measured outgoing bitrate while live.
  final int? bitrateKbps;
  final int? uptimeMs;

  /// Last error or disconnection reason.
  final String? message;

  bool get active => state != BroadcastStreamState.idle && state != BroadcastStreamState.failed;

  Json toJson() => {
        'state': state.name,
        'configured': configured,
        'server': server,
        'targetKbps': targetKbps,
        'audio': audio,
        if (keyHint != null) 'keyHint': keyHint,
        if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
        if (uptimeMs != null) 'uptimeMs': uptimeMs,
        if (message != null) 'message': message,
      };
}

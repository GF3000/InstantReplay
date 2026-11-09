import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../l10n/app_localizations.dart';
import '../recording/recording_widgets.dart' show formatRecordingClock;
import 'scoreboard_controller.dart' show periodLabel;

// Broadcast mode (SPEC §12) as both roles show it: the Camera for its own stream controls, every
// Viewer for the scoreboard and the stream from the status the Camera pushes.

// region Stream

String broadcastStateLabel(AppLocalizations l10n, BroadcastStreamState state) => switch (state) {
      BroadcastStreamState.idle => l10n.broadcastStateIdle,
      BroadcastStreamState.connecting => l10n.broadcastStateConnecting,
      BroadcastStreamState.live => l10n.broadcastStateLive,
      BroadcastStreamState.reconnecting => l10n.broadcastStateReconnecting,
      BroadcastStreamState.failed => l10n.broadcastStateFailed,
    };

Color broadcastStateColor(BroadcastStreamState state, {bool dim = false}) => switch (state) {
      BroadcastStreamState.live => dim ? const Color(0xFF8A2A2A) : const Color(0xFFE53935),
      BroadcastStreamState.connecting || BroadcastStreamState.reconnecting =>
        dim ? const Color(0xFF7A6020) : const Color(0xFFFFB300),
      BroadcastStreamState.failed => dim ? const Color(0xFF8A2A2A) : const Color(0xFFB71C1C),
      BroadcastStreamState.idle => const Color(0xFF7A7A7A),
    };

/// Why a broadcast command was refused, from the Camera's error code.
String broadcastErrorMessage(AppLocalizations l10n, String code, String? message) => switch (code) {
      'not_configured' => l10n.broadcastNotConfigured,
      'mic_permission' => l10n.broadcastMicDenied,
      'not_broadcast_mode' => l10n.broadcastNotBroadcastMode,
      _ => l10n.broadcastFailed(message ?? code),
    };

/// The second line under the state: bitrate and time on air, the last error, or what is missing.
String broadcastDetail(AppLocalizations l10n, BroadcastInfo info) {
  final numbers = [
    if (info.bitrateKbps case final kbps?) l10n.broadcastBitrate((kbps / 1000).toStringAsFixed(1)),
    if (info.uptimeMs case final ms?) formatRecordingClock(ms),
  ].join(' · ');
  return switch (info.state) {
    BroadcastStreamState.live || BroadcastStreamState.connecting => numbers,
    BroadcastStreamState.reconnecting || BroadcastStreamState.failed =>
      [?info.message, if (numbers.isNotEmpty) numbers].join(' · '),
    BroadcastStreamState.idle => info.configured ? l10n.broadcastReady(info.targetKbps) : l10n.broadcastNotConfigured,
  };
}

/// One compact row: the stream state and numbers on the left, settings and Go live / Stop on the
/// right. Stop asks first.
class BroadcastBar extends StatelessWidget {
  const BroadcastBar({
    super.key,
    required this.info,
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onConfigure,
    this.keyPrefix = 'broadcast',
    this.buttonSize = 48,
    this.dim = false,
  });

  final BroadcastInfo info;

  /// False while the Camera is not reachable or not capturing.
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onConfigure;

  /// Prefix of the buttons' keys, e.g. `viewer-broadcast` → `viewer-broadcast-start`.
  final String keyPrefix;
  final double buttonSize;

  /// The Camera's black operating screen.
  final bool dim;

  static const _dim = Color(0xFF5A5A5A);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = broadcastStateColor(info.state, dim: dim);
    final detail = broadcastDetail(l10n, info);
    final size = buttonSize;
    final fg = dim ? _dim : null;
    final side = dim ? const BorderSide(color: _dim) : null;
    return Row(children: [
      Icon(info.state == BroadcastStreamState.live ? Icons.sensors : Icons.sensors_off, size: 20, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            broadcastStateLabel(l10n, info.state),
            key: ValueKey('$keyPrefix-state'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: dim ? color : null, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: dim ? _dim : theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ]),
      ),
      if (!dim)
        IconButton(
          key: ValueKey('$keyPrefix-settings'),
          tooltip: l10n.broadcastSettings,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          onPressed: enabled ? onConfigure : null,
          icon: const Icon(Icons.settings),
        ),
      const SizedBox(width: 4),
      if (info.active)
        OutlinedButton.icon(
          key: ValueKey('$keyPrefix-stop'),
          style: OutlinedButton.styleFrom(minimumSize: Size(size, size), foregroundColor: fg, side: side),
          onPressed: enabled ? () => _stop(context) : null,
          icon: const Icon(Icons.stop),
          label: Text(l10n.broadcastStop),
        )
      else
        FilledButton.icon(
          key: ValueKey('$keyPrefix-start'),
          style: FilledButton.styleFrom(
            minimumSize: Size(size, size),
            backgroundColor: dim ? Colors.transparent : const Color(0xFFC62828),
            foregroundColor: dim ? _dim : Colors.white,
            side: side,
          ),
          onPressed: enabled && info.configured ? onStart : (enabled ? onConfigure : null),
          icon: const Icon(Icons.sensors),
          label: Text(l10n.broadcastStart, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
    ]);
  }

  Future<void> _stop(BuildContext context) async {
    if (await confirmStopBroadcast(context)) onStop();
  }
}

/// True to end the stream.
Future<bool> confirmStopBroadcast(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final stop = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.broadcastStopTitle),
      content: Text(l10n.broadcastStopBody),
      actions: [
        TextButton(
          key: const ValueKey('broadcast-stop-keep'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.broadcastStopKeep),
        ),
        FilledButton(
          key: const ValueKey('broadcast-stop-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.broadcastStop),
        ),
      ],
    ),
  );
  return stop ?? false;
}

/// What the stream settings dialog returns. [key] null keeps the stored key.
typedef BroadcastConfigResult = ({String server, String? key, int targetKbps, bool audio});

/// Server, stream key (hidden, paste-friendly), bitrate and microphone. The stored key never
/// comes back to the screen: an empty field keeps it.
Future<BroadcastConfigResult?> showBroadcastConfigDialog(BuildContext context, BroadcastInfo info) =>
    showDialog<BroadcastConfigResult>(context: context, builder: (_) => _BroadcastConfigDialog(info: info));

class _BroadcastConfigDialog extends StatefulWidget {
  const _BroadcastConfigDialog({required this.info});

  final BroadcastInfo info;

  @override
  State<_BroadcastConfigDialog> createState() => _BroadcastConfigDialogState();
}

class _BroadcastConfigDialogState extends State<_BroadcastConfigDialog> {
  late final _server = TextEditingController(text: widget.info.server);
  final _key = TextEditingController();
  late int _kbps = widget.info.targetKbps.clamp(BroadcastInfo.minKbps, BroadcastInfo.maxKbps);
  late bool _audio = widget.info.audio;
  bool _showKey = false;

  @override
  void dispose() {
    _server.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) setState(() => _key.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hint = widget.info.keyHint;
    return AlertDialog(
      title: Text(l10n.broadcastSettings),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const ValueKey('broadcast-key'),
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.broadcastKey,
              hintText: hint == null ? null : '•••• $hint',
              helperText: hint == null ? l10n.broadcastKeyHelp : l10n.broadcastKeyKeep(hint),
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: l10n.broadcastPaste, icon: const Icon(Icons.content_paste), onPressed: _paste),
                IconButton(
                  tooltip: _showKey ? l10n.broadcastKeyHide : l10n.broadcastKeyShow,
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('broadcast-server'),
            controller: _server,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l10n.broadcastServer, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(l10n.broadcastBitrateLabel(_kbps)),
          Slider(
            key: const ValueKey('broadcast-kbps'),
            value: _kbps.toDouble(),
            min: BroadcastInfo.minKbps.toDouble(),
            max: BroadcastInfo.maxKbps.toDouble(),
            divisions: (BroadcastInfo.maxKbps - BroadcastInfo.minKbps) ~/ 250,
            label: '$_kbps',
            onChanged: (v) => setState(() => _kbps = v.round()),
          ),
          SwitchListTile(
            key: const ValueKey('broadcast-audio'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.broadcastAudio),
            value: _audio,
            onChanged: (v) => setState(() => _audio = v),
          ),
        ]),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('broadcast-config-save'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () {
            final key = _key.text.trim();
            Navigator.of(context).pop((
              server: _server.text.trim().isEmpty ? BroadcastInfo.defaultServer : _server.text.trim(),
              key: key.isEmpty ? null : key,
              targetKbps: _kbps,
              audio: _audio,
            ));
          },
          child: Text(l10n.broadcastSave),
        ),
      ],
    );
  }
}

// endregion

// region Scoreboard

/// Team colours to choose from: readable on air and distinct from each other.
const teamPalette = <int>[
  0xFF1E88E5, // blue
  0xFF0D2B6B, // navy
  0xFFE53935, // red
  0xFF8E1B1B, // maroon
  0xFF43A047, // green
  0xFFFDD835, // yellow
  0xFFFB8C00, // orange
  0xFF8E24AA, // purple
  0xFF212121, // black
  0xFFFAFAFA, // white
];

/// Black or white, whichever reads better on [background].
Color onColor(Color background) => background.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// Rebuilds [builder] with the clock value while a scoreboard clock runs, starting from [state]'s
/// value at the moment the state arrived (a new state object re-anchors it).
class ScoreboardClock extends StatefulWidget {
  const ScoreboardClock({super.key, required this.state, required this.builder});

  final ScoreboardState state;
  final Widget Function(BuildContext context, int clockMs) builder;

  @override
  State<ScoreboardClock> createState() => _ScoreboardClockState();
}

class _ScoreboardClockState extends State<ScoreboardClock> {
  final _since = Stopwatch()..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ScoreboardClock old) {
    super.didUpdateWidget(old);
    if (!identical(old.state, widget.state)) {
      _since
        ..reset()
        ..start();
      _schedule();
    }
  }

  void _schedule() {
    _tick?.cancel();
    _tick = widget.state.clockRunning
        ? Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.state.clockAt(_since.elapsedMilliseconds));
}

/// The scoreboard controls (SPEC §12.2), pressed under stress during a match: per team the name
/// in its colour, the score and big, spaced + and − buttons; in the middle the clock (tap to
/// set), start/stop, the period, and the overlay toggle, reset and settings.
class ScoreboardPanel extends StatelessWidget {
  const ScoreboardPanel({
    super.key,
    required this.state,
    required this.enabled,
    required this.onCommand,
    this.compact = false,
  });

  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand command) onCommand;

  /// Short screens: smaller buttons and figures.
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final home = _TeamControl(team: Team.home, state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        final away = _TeamControl(team: Team.away, state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        final centre = _CentreControl(state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        if (c.maxWidth >= 620) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: home),
            const SizedBox(width: 8),
            centre,
            const SizedBox(width: 8),
            Expanded(child: away),
          ]);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [Expanded(child: home), const SizedBox(width: 12), Expanded(child: away)]),
          const SizedBox(height: 4),
          centre,
        ]);
      });
}

class _TeamControl extends StatelessWidget {
  const _TeamControl({
    required this.team,
    required this.state,
    required this.enabled,
    required this.onCommand,
    required this.compact,
  });

  final Team team;
  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = state.team(team);
    final color = Color(t.color);
    final plus = compact ? 60.0 : 76.0;
    final minus = compact ? 44.0 : 52.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(
          t.name.toUpperCase(),
          key: ValueKey('score-${team.name}-name'),
          style: TextStyle(color: onColor(color), fontWeight: FontWeight.w900, fontSize: compact ? 16 : 18, letterSpacing: 1),
        ),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.outlined(
          key: ValueKey('score-${team.name}-minus'),
          tooltip: l10n.scoreboardMinus(t.name),
          constraints: BoxConstraints.tightFor(width: minus, height: minus),
          onPressed: enabled && t.score > 0 ? () => onCommand(ScoreCommand(team: team, delta: -1)) : null,
          icon: const Icon(Icons.remove),
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: compact ? 56 : 72),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${t.score}',
                key: ValueKey('score-${team.name}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 40 : 52,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: plus,
          height: plus,
          child: FilledButton(
            key: ValueKey('score-${team.name}-plus'),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: color,
              foregroundColor: onColor(color),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              side: color.computeLuminance() > 0.8 ? const BorderSide(color: Colors.black26) : null,
            ),
            onPressed: enabled ? () => onCommand(ScoreCommand(team: team, delta: 1)) : null,
            child: Icon(Icons.add, size: compact ? 36 : 44, semanticLabel: l10n.scoreboardPlus(t.name)),
          ),
        ),
      ]),
    ]);
  }
}

class _CentreControl extends StatelessWidget {
  const _CentreControl({required this.state, required this.enabled, required this.onCommand, required this.compact});

  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final label = periodLabel(l10n, period: state.period, periods: state.periods);
    final play = compact ? 52.0 : 60.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          key: const ValueKey('score-clock'),
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => _setClock(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: ScoreboardClock(
              state: state,
              builder: (context, ms) => Text(
                formatClock(ms),
                semanticsLabel: l10n.scoreboardSetClock,
                style: TextStyle(
                  fontSize: compact ? 34 : 42,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: state.clockRunning ? null : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: play,
          height: play,
          child: FilledButton.tonal(
            key: const ValueKey('score-clock-toggle'),
            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder()),
            onPressed: enabled
                ? () => onCommand(state.clockRunning ? const ClockPauseCommand() : const ClockStartCommand())
                : null,
            child: Icon(
              state.clockRunning ? Icons.pause : Icons.play_arrow,
              size: compact ? 32 : 38,
              semanticLabel: state.clockRunning ? l10n.scoreboardPauseClock : l10n.scoreboardStartClock,
            ),
          ),
        ),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (state.periods > 1) ...[
          IconButton(
            key: const ValueKey('score-period-prev'),
            tooltip: l10n.scoreboardPeriodPrev,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: enabled && state.period > 1 ? () => onCommand(const PeriodCommand(delta: -1)) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          SizedBox(
            width: 40,
            child: Text(
              label,
              key: const ValueKey('score-period'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          IconButton(
            key: const ValueKey('score-period-next'),
            tooltip: l10n.scoreboardPeriodNext,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            onPressed: enabled && state.period < state.periods ? () => onCommand(const PeriodCommand(delta: 1)) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          key: const ValueKey('score-visible'),
          tooltip: l10n.scoreboardVisible,
          isSelected: state.visible,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled ? () => onCommand(VisibleCommand(visible: !state.visible)) : null,
          icon: const Icon(Icons.visibility_off),
          selectedIcon: const Icon(Icons.visibility),
        ),
        IconButton(
          key: const ValueKey('score-reset'),
          tooltip: l10n.scoreboardReset,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled ? () => _reset(context) : null,
          icon: const Icon(Icons.restart_alt),
        ),
        IconButton(
          key: const ValueKey('score-settings'),
          tooltip: l10n.scoreboardSettings,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled ? () => _settings(context) : null,
          icon: const Icon(Icons.tune),
        ),
      ]),
    ]);
  }

  Future<void> _setClock(BuildContext context) async {
    final ms = await showClockSetDialog(context, state.clockAt(0));
    if (ms != null) onCommand(ClockSetCommand(ms: ms));
  }

  Future<void> _reset(BuildContext context) async {
    if (await confirmScoreboardReset(context)) onCommand(const ResetCommand());
  }

  Future<void> _settings(BuildContext context) async {
    final settings = await showScoreboardSettingsDialog(context, state.settings);
    if (settings != null) onCommand(SettingsCommand(settings));
  }
}

/// `12:30` → 750000 ms; also plain minutes (`45`). Null when it does not parse.
int? parseClock(String text) {
  final m = RegExp(r'^\s*(\d{1,3})(?:\s*[:.,]\s*(\d{1,2}))?\s*$').firstMatch(text);
  if (m == null) return null;
  final minutes = int.parse(m[1]!);
  final seconds = m[2] == null ? 0 : int.parse(m[2]!);
  if (seconds >= 60) return null;
  return (minutes * 60 + seconds) * 1000;
}

/// Asks for a clock value as `mm:ss`; null when cancelled.
Future<int?> showClockSetDialog(BuildContext context, int currentMs) =>
    showDialog<int>(context: context, builder: (_) => _ClockSetDialog(initial: formatClock(currentMs)));

class _ClockSetDialog extends StatefulWidget {
  const _ClockSetDialog({required this.initial});

  final String initial;

  @override
  State<_ClockSetDialog> createState() => _ClockSetDialogState();
}

class _ClockSetDialogState extends State<_ClockSetDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  bool _invalid = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final ms = parseClock(_text.text);
    if (ms == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(ms);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.scoreboardSetClock),
      content: TextField(
        key: const ValueKey('score-clock-field'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.datetime,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 32, fontFeatures: [FontFeature.tabularFigures()]),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9:.,]'))],
        decoration: InputDecoration(
          hintText: l10n.scoreboardSetClockHint,
          errorText: _invalid ? l10n.scoreboardInvalidTime : null,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('score-clock-set'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: _submit,
          child: Text(l10n.scoreboardSet),
        ),
      ],
    );
  }
}

/// True to reset scores, period and clock.
Future<bool> confirmScoreboardReset(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final reset = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.scoreboardResetTitle),
      content: Text(l10n.scoreboardResetBody),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('score-reset-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.scoreboardReset),
        ),
      ],
    ),
  );
  return reset ?? false;
}

/// Team names and colours, periods, period length and clock direction; null when cancelled.
Future<ScoreboardSettings?> showScoreboardSettingsDialog(BuildContext context, ScoreboardSettings current) =>
    showDialog<ScoreboardSettings>(context: context, builder: (_) => _SettingsDialog(current: current));

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.current});

  final ScoreboardSettings current;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _homeName = TextEditingController(text: widget.current.homeName);
  late final _awayName = TextEditingController(text: widget.current.awayName);
  late final _minutes = TextEditingController(text: '${widget.current.periodMs ~/ 60000}');
  late int _homeColor = widget.current.homeColor;
  late int _awayColor = widget.current.awayColor;
  late int _periods = widget.current.periods.clamp(1, ScoreboardState.maxPeriods);
  late bool _countDown = widget.current.countDown;

  @override
  void dispose() {
    _homeName.dispose();
    _awayName.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget team(String title, TextEditingController name, int color, ValueChanged<int> onColor, String key) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('score-settings-$key-name'),
              controller: name,
              maxLength: ScoreboardState.maxNameLength,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: l10n.scoreboardTeamName, border: const OutlineInputBorder()),
            ),
            _Palette(selected: color, onSelected: onColor, keyPrefix: 'score-settings-$key-color', label: title),
          ],
        );

    return AlertDialog(
      title: Text(l10n.scoreboardSettings),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          team(l10n.scoreboardHome, _homeName, _homeColor, (c) => setState(() => _homeColor = c), 'home'),
          const SizedBox(height: 16),
          team(l10n.scoreboardAway, _awayName, _awayColor, (c) => setState(() => _awayColor = c), 'away'),
          const SizedBox(height: 16),
          Text(l10n.scoreboardPeriods, style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const ValueKey('score-settings-periods'),
            showSelectedIcon: false,
            segments: [
              for (var p = 1; p <= ScoreboardState.maxPeriods; p++) ButtonSegment(value: p, label: Text('$p')),
            ],
            selected: {_periods},
            onSelectionChanged: (s) => setState(() => _periods = s.single),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('score-settings-minutes'),
            controller: _minutes,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(labelText: l10n.scoreboardPeriodMinutes, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(l10n.scoreboardClockDirection, style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const ValueKey('score-settings-direction'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, icon: const Icon(Icons.arrow_upward), label: Text(l10n.scoreboardCountUp)),
              ButtonSegment(value: true, icon: const Icon(Icons.arrow_downward), label: Text(l10n.scoreboardCountDown)),
            ],
            selected: {_countDown},
            onSelectionChanged: (s) => setState(() => _countDown = s.single),
          ),
        ]),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('score-settings-save'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () {
            final minutes = int.tryParse(_minutes.text) ?? widget.current.periodMs ~/ 60000;
            Navigator.of(context).pop(ScoreboardSettings(
              homeName: ScoreboardState.normalizeName(_homeName.text, widget.current.homeName),
              awayName: ScoreboardState.normalizeName(_awayName.text, widget.current.awayName),
              homeColor: _homeColor,
              awayColor: _awayColor,
              periods: _periods,
              periodMs: minutes.clamp(1, 120) * 60000,
              countDown: _countDown,
            ));
          },
          child: Text(l10n.broadcastSave),
        ),
      ],
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.selected, required this.onSelected, required this.keyPrefix, required this.label});

  final int selected;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outline = Theme.of(context).colorScheme.outline;
    return Semantics(
      label: l10n.scoreboardTeamColor(label),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (i, c) in teamPalette.indexed)
          InkResponse(
            key: ValueKey('$keyPrefix-$i'),
            onTap: () => onSelected(c),
            radius: 24,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == selected ? onColor(Color(c)) : outline, width: c == selected ? 3 : 1),
                boxShadow: c == selected ? [BoxShadow(color: outline, spreadRadius: 2)] : null,
              ),
              child: c == selected ? Icon(Icons.check, color: onColor(Color(c)), size: 20) : null,
            ),
          ),
      ]),
    );
  }
}

// endregion

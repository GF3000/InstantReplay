import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../scoreboard_controller.dart' show periodLabel;
import 'scoreboard_settings_page.dart';

// The scoreboard controls (SPEC §12.2) as the Camera and every Viewer show them.

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

/// The scoreboard strip, pressed under stress during a match: per team its name with the colour
/// bar, the score in big figures, a small −1 and a big +1 key in the team colour (the score sits
/// between them, so they are never next to each other); in the middle the clock in amber (hold to
/// set), start/pause, and the period with a menu for the rare actions.
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

  /// Short screens (a phone on its side): smaller keys and figures.
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final home = _TeamControl(team: Team.home, state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        final away = _TeamControl(
            team: Team.away, state: state, enabled: enabled, onCommand: onCommand, compact: compact, mirrored: true);
        final centre = _CentreControl(state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        final gap = compact ? 8.0 : 16.0;
        if (c.maxWidth >= (compact ? 340 : 620)) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: home),
            SizedBox(width: gap),
            centre,
            SizedBox(width: gap),
            Expanded(child: away),
          ]);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [Expanded(child: home), const SizedBox(width: 12), Expanded(child: away)]),
          const SizedBox(height: 6),
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
    this.mirrored = false,
  });

  final Team team;
  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;
  final bool compact;

  /// The away team: +1 towards the middle, −1 on the outer edge.
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final t = state.team(team);
    final color = Color(t.color);
    final keyHeight = compact ? 56.0 : 68.0;
    final minus = SizedBox(
      width: compact ? 44 : 60,
      height: keyHeight,
      child: IrKey(
        key: ValueKey('score-${team.name}-minus'),
        minHeight: keyHeight,
        padding: EdgeInsets.zero,
        semanticLabel: l10n.scoreboardMinus(t.name),
        onPressed: enabled && t.score > 0 ? () => onCommand(ScoreCommand(team: team, delta: -1)) : null,
        child: Text('−1', style: irMono(compact ? 16 : 22, color: c.text)),
      ),
    );
    final plus = SizedBox(
      width: compact ? 56 : 88,
      height: keyHeight,
      child: IrKey(
        key: ValueKey('score-${team.name}-plus'),
        minHeight: keyHeight,
        padding: EdgeInsets.zero,
        borderColor: color,
        led: color,
        semanticLabel: l10n.scoreboardPlus(t.name),
        onPressed: enabled ? () => onCommand(ScoreCommand(team: team, delta: 1)) : null,
        child: Text('+1', style: irMono(compact ? 18 : 24, color: c.text)),
      ),
    );
    final score = Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${t.score}',
          key: ValueKey('score-${team.name}'),
          textAlign: TextAlign.center,
          style: irMono(compact ? 34 : 64, color: c.text, height: 1),
        ),
      ),
    );
    final bar = Container(width: compact ? 4 : 5, height: compact ? 13 : 18, color: color);
    final name = Flexible(
      child: Text(
        t.name.toUpperCase(),
        key: ValueKey('score-${team.name}-name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 13 : 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: c.muted,
        ),
      ),
    );
    final gap = SizedBox(width: compact ? 4 : 8);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(
        mainAxisAlignment: mirrored ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: mirrored ? [name, const SizedBox(width: 6), bar] : [bar, const SizedBox(width: 6), name],
      ),
      SizedBox(height: compact ? 4 : 8),
      Row(children: mirrored ? [plus, gap, score, gap, minus] : [minus, gap, score, gap, plus]),
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
    final c = context.ir;
    final running = state.clockRunning;
    final toggle = IrKey(
      key: const ValueKey('score-clock-toggle'),
      minHeight: 48,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      borderColor: running ? c.ok : null,
      semanticLabel: running ? l10n.scoreboardPauseClock : l10n.scoreboardStartClock,
      onPressed: enabled ? () => onCommand(running ? const ClockPauseCommand() : const ClockStartCommand()) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(running ? Icons.pause : Icons.play_arrow, size: compact ? 22 : 24, color: running ? c.ok : c.text),
        if (!compact) ...[
          const SizedBox(width: 6),
          Text(
            running ? l10n.scoreboardPauseClock : l10n.scoreboardStartClock,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: running ? c.ok : c.text),
          ),
        ],
      ]),
    );
    final menu = _ScoreboardMenu(state: state, enabled: enabled, onCommand: onCommand, compact: compact);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // A long press, so a stray tap during the match never opens the editor.
      InkWell(
        key: const ValueKey('score-clock'),
        borderRadius: BorderRadius.circular(4),
        onTap: enabled ? () => _holdHint(context) : null,
        onLongPress: enabled ? () => _setClock(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: ScoreboardClock(
            state: state,
            builder: (context, ms) => Text(
              formatClock(ms),
              semanticsLabel: l10n.scoreboardSetClock,
              style: irMono(compact ? 24 : 46, color: running ? c.signal : c.warnText, height: 1.1),
            ),
          ),
        ),
      ),
      SizedBox(height: compact ? 2 : 8),
      if (compact)
        Row(mainAxisSize: MainAxisSize.min, children: [toggle, const SizedBox(width: 4), menu])
      else ...[
        toggle,
        const SizedBox(height: 4),
        menu,
      ],
    ]);
  }

  void _holdHint(BuildContext context) {
    final text = AppLocalizations.of(context).scoreboardHoldToSetClock;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _setClock(BuildContext context) async {
    unawaited(HapticFeedback.mediumImpact());
    final ms = await showClockSetDialog(context, state.clockAt(0));
    if (ms != null) onCommand(ClockSetCommand(ms: ms));
  }
}

enum _MenuAction { nextPeriod, prevPeriod, visible, reset, settings }

/// The period label plus a menu with the actions used a few times per match.
class _ScoreboardMenu extends StatelessWidget {
  const _ScoreboardMenu({required this.state, required this.enabled, required this.onCommand, required this.compact});

  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    String label(int period) => periodLabel(l10n, period: period, periods: state.periods);
    final hasPeriods = state.periods > 1;
    return PopupMenuButton<_MenuAction>(
      key: const ValueKey('score-menu'),
      enabled: enabled,
      tooltip: l10n.scoreboardMore,
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        if (hasPeriods && state.period < state.periods)
          PopupMenuItem(
            key: const ValueKey('score-period-next'),
            value: _MenuAction.nextPeriod,
            child: ListTile(
              leading: const Icon(Icons.skip_next),
              title: Text(l10n.scoreboardGoToPeriod(label(state.period + 1))),
            ),
          ),
        if (hasPeriods && state.period > 1)
          PopupMenuItem(
            key: const ValueKey('score-period-prev'),
            value: _MenuAction.prevPeriod,
            child: ListTile(
              leading: const Icon(Icons.skip_previous),
              title: Text(l10n.scoreboardBackToPeriod(label(state.period - 1))),
            ),
          ),
        if (hasPeriods) const PopupMenuDivider(),
        CheckedPopupMenuItem(
          key: const ValueKey('score-visible'),
          value: _MenuAction.visible,
          checked: state.visible,
          child: Text(l10n.scoreboardVisible),
        ),
        PopupMenuItem(
          key: const ValueKey('score-reset'),
          value: _MenuAction.reset,
          child: ListTile(leading: const Icon(Icons.restart_alt), title: Text(l10n.scoreboardReset)),
        ),
        PopupMenuItem(
          key: const ValueKey('score-settings'),
          value: _MenuAction.settings,
          child: ListTile(leading: const Icon(Icons.tune), title: Text(l10n.scoreboardSettings)),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (hasPeriods) ...[
              Text(
                label(state.period),
                key: const ValueKey('score-period'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 15 : 17, color: c.text),
              ),
              const SizedBox(width: 6),
            ],
            if (!state.visible) ...[
              Icon(Icons.visibility_off, size: 20, color: c.warnText, semanticLabel: l10n.scoreboardHidden),
              const SizedBox(width: 6),
            ],
            Icon(Icons.more_horiz, color: c.muted),
          ]),
        ),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _MenuAction action) async {
    switch (action) {
      case _MenuAction.nextPeriod:
      case _MenuAction.prevPeriod:
        final delta = action == _MenuAction.nextPeriod ? 1 : -1;
        if (await _confirmPeriod(context, state.period + delta)) onCommand(PeriodCommand(delta: delta));
      case _MenuAction.visible:
        onCommand(VisibleCommand(visible: !state.visible));
      case _MenuAction.reset:
        if (await confirmScoreboardReset(context)) onCommand(const ResetCommand());
      case _MenuAction.settings:
        final settings = await showScoreboardSettingsDialog(context, state.settings, state: state);
        if (settings != null) onCommand(SettingsCommand(settings));
    }
  }

  /// A period change stops and resets the clock, so it asks first.
  Future<bool> _confirmPeriod(BuildContext context, int period) async {
    final l10n = AppLocalizations.of(context);
    final label = periodLabel(l10n, period: period, periods: state.periods);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.scoreboardPeriodConfirmTitle(label)),
        content: Text(l10n.scoreboardPeriodConfirmBody(formatClock(state.periodStartMs))),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.broadcastCancel),
          ),
          FilledButton(
            key: const ValueKey('score-period-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.scoreboardPeriodConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Asks for a clock value with minute and second wheels, like the Android alarm picker; null when
/// cancelled.
Future<int?> showClockSetDialog(BuildContext context, int currentMs) =>
    showDialog<int>(context: context, builder: (_) => _ClockSetDialog(initialMs: currentMs));

class _ClockSetDialog extends StatefulWidget {
  const _ClockSetDialog({required this.initialMs});

  final int initialMs;

  @override
  State<_ClockSetDialog> createState() => _ClockSetDialogState();
}

class _ClockSetDialogState extends State<_ClockSetDialog> {
  static const maxMinutes = 199;

  late final _minutes = FixedExtentScrollController(initialItem: (widget.initialMs ~/ 60000).clamp(0, maxMinutes));
  late final _seconds = FixedExtentScrollController(initialItem: widget.initialMs ~/ 1000 % 60);

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _submit() {
    // The seconds wheel loops, so its index can run past 59 or below 0.
    final ms = (_minutes.selectedItem * 60 + _seconds.selectedItem % 60) * 1000;
    Navigator.of(context).pop(ms);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return AlertDialog(
      title: Text(l10n.scoreboardSetClock),
      content: SizedBox(
        height: _Wheel.itemExtent * 5,
        child: Stack(alignment: Alignment.center, children: [
          // The selection band, as in the Android alarm picker.
          Container(
            height: _Wheel.itemExtent,
            decoration: BoxDecoration(
              color: c.signalSoft,
              border: Border.all(color: c.signal),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _Wheel(
              key: const ValueKey('score-clock-minutes'),
              controller: _minutes,
              count: maxMinutes + 1,
              looping: false,
              semanticLabel: l10n.scoreboardMinutes,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(':', style: irMono(_Wheel.fontSize, color: c.signal)),
            ),
            _Wheel(
              key: const ValueKey('score-clock-seconds'),
              controller: _seconds,
              count: 60,
              looping: true,
              semanticLabel: l10n.scoreboardSeconds,
            ),
          ]),
        ]),
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

/// One two-digit wheel. Dragged with a finger, a mouse (web viewer) or the mouse wheel.
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.count,
    required this.looping,
    required this.semanticLabel,
  });

  static const itemExtent = 56.0;
  static const fontSize = 36.0;

  final FixedExtentScrollController controller;
  final int count;
  final bool looping;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = context.ir.text;
    Widget item(int i) => Center(
          child: Text((i % count).toString().padLeft(2, '0'), style: irMono(fontSize, color: color)),
        );
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: 84,
        child: ScrollConfiguration(
          // Flutter web doesn't drag scrollables with a mouse by default.
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {...PointerDeviceKind.values}, scrollbars: false),
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: itemExtent,
            diameterRatio: 1.6,
            overAndUnderCenterOpacity: 0.45,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (_) => HapticFeedback.selectionClick(),
            childDelegate: looping
                ? ListWheelChildLoopingListDelegate(children: [for (var i = 0; i < count; i++) item(i)])
                : ListWheelChildBuilderDelegate(childCount: count, builder: (context, i) => item(i)),
          ),
        ),
      ),
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

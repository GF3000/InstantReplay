import 'dart:async';

import 'package:flutter/material.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';

// Replays on air (SPEC §12.6) as both roles show them: every Viewer from status.replay, the Camera
// from its own replay controller.

/// `0:07 / 0:20`
String formatReplayTime(int ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// What a replay is at [elapsedMs] after [replay] was reported: it advances at its speed and
/// stops at the end of the clip.
int replayPositionAt(ReplayInfo replay, int elapsedMs) {
  final position = replay.positionMs + (elapsedMs * replay.speed).round();
  return replay.durationMs > 0 ? position.clamp(0, replay.durationMs) : position;
}

/// A compact bar while a clip is on air, outlined in live red: "REPLAY ON AIR" and the clip's
/// progress, the speed (0.25× / 0.5× / 1×, changeable at any time) and a big Back to live.
class ReplayBar extends StatefulWidget {
  const ReplayBar({
    super.key,
    required this.replay,
    required this.enabled,
    required this.onSpeed,
    required this.onStop,
    this.keyPrefix = 'replay',
  });

  /// As last reported; a new object re-anchors the progress.
  final ReplayInfo replay;

  /// False while the Camera is not reachable.
  final bool enabled;
  /// Null hides the speed control: the review page drives the speed with its own (one control
  /// for what the tablet and the stream show).
  final ValueChanged<double>? onSpeed;
  final VoidCallback onStop;

  /// Prefix of the keys, e.g. `viewer-replay` → `viewer-replay-stop`, `viewer-replay-speed-0.5`.
  final String keyPrefix;

  @override
  State<ReplayBar> createState() => _ReplayBarState();
}

class _ReplayBarState extends State<ReplayBar> {
  final _since = Stopwatch()..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ReplayBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.replay, widget.replay)) {
      _since
        ..reset()
        ..start();
      _schedule();
    }
  }

  int get _position => replayPositionAt(widget.replay, _since.elapsedMilliseconds);

  static const _every = Duration(milliseconds: 250);

  void _schedule() {
    _tick?.cancel();
    final r = widget.replay;
    // Ticks until the end of the clip (and one more): nothing moves after it.
    final left = r.durationMs <= 0 || r.speed <= 0 ? 0 : ((r.durationMs - r.positionMs) / r.speed);
    final ticks = (left / _every.inMilliseconds).ceil() + 1;
    _tick = Timer.periodic(_every, (t) {
      if (!mounted) return;
      if (t.tick >= ticks || _position >= r.durationMs) t.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final r = widget.replay;
    final prefix = widget.keyPrefix;
    final position = _position;
    final progress = r.durationMs > 0 ? position / r.durationMs : 0.0;
    final selected = ReplayInfo.speeds.contains(r.speed) ? r.speed : null;
    final onSpeed = widget.onSpeed;
    final speed = onSpeed == null
        ? null
        : _SpeedStrip(
            key: ValueKey('$prefix-speed'),
            prefix: prefix,
            selected: selected,
            tooltip: l10n.replaySpeed,
            label: (s) => l10n.viewerReviewSpeed(s),
            onChanged: widget.enabled ? onSpeed : null,
          );
    final back = FilledButton.icon(
      key: ValueKey('$prefix-stop'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: c.live,
        foregroundColor: c.onLive,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: widget.enabled ? widget.onStop : null,
      icon: const Icon(Icons.live_tv),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(l10n.replayBackToLive, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
    final header = Row(
      children: [
        IrLiveDot(color: c.live, size: 9),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.replayOnAir,
            key: ValueKey('$prefix-label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: irMono(13, color: c.liveText).copyWith(letterSpacing: 1.2),
          ),
        ),
        Text(
          '${formatReplayTime(position)} / ${formatReplayTime(r.durationMs)}',
          key: ValueKey('$prefix-time'),
          style: irMono(13, weight: FontWeight.w600, color: c.text),
        ),
      ],
    );
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 3,
        color: c.live,
        backgroundColor: c.line,
      ),
    );
    return Container(
      key: ValueKey(prefix),
      decoration: BoxDecoration(
        color: c.liveSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.live),
      ),
      padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
      child: LayoutBuilder(
        builder: (context, box) {
          // Wide: one row. Narrow (a phone, a side panel): progress on top, controls below.
          if (box.maxWidth >= 560) {
            return Row(
              children: [
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [header, const SizedBox(height: 6), bar]),
                ),
                if (speed != null) ...[const SizedBox(width: 10), SizedBox(width: 180, child: speed)],
                const SizedBox(width: 8),
                back,
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.only(right: 4), child: header),
              const SizedBox(height: 2),
              Padding(padding: const EdgeInsets.only(right: 4), child: bar),
              const SizedBox(height: 3),
              Row(
                children: [
                  if (speed != null) ...[SizedBox(width: 150, child: speed), const SizedBox(width: 6)],
                  Expanded(child: back),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 0.25× / 0.5× / 1× in the control-room style, with a key per speed (`<prefix>-speed-0.5`).
class _SpeedStrip extends StatelessWidget {
  const _SpeedStrip({
    super.key,
    required this.prefix,
    required this.selected,
    required this.tooltip,
    required this.label,
    required this.onChanged,
  });

  final String prefix;
  final double? selected;
  final String tooltip;
  final String Function(double) label;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          for (final (i, s) in ReplayInfo.speeds.indexed) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, color: c.line),
            Expanded(
              child: Semantics(
                selected: s == selected,
                button: true,
                child: Material(
                  color: s == selected ? c.signal : c.surface,
                  child: InkWell(
                    onTap: onChanged == null ? null : () => onChanged!(s),
                    child: Center(
                      child: Text(
                        label(s),
                        key: ValueKey('$prefix-speed-$s'),
                        maxLines: 1,
                        style: irMono(14, weight: FontWeight.w600, color: s == selected ? c.onSignal : c.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

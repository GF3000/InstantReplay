import 'dart:async';

import 'package:flutter/material.dart';
import 'package:replay_protocol/replay_protocol.dart';

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

/// A compact bar while a clip is on air: the label and the clip's progress, the speed
/// (0.25× / 0.5× / 1×, changeable at any time) and a big Back to live.
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
  final ValueChanged<double> onSpeed;
  final VoidCallback onStop;

  /// Prefix of the keys, e.g. `viewer-replay` → `viewer-replay-stop`, `viewer-replay-speed-0.5`.
  final String keyPrefix;

  static const _onAir = Color(0xFFE53935);

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
    final theme = Theme.of(context);
    final r = widget.replay;
    final prefix = widget.keyPrefix;
    final position = _position;
    final progress = r.durationMs > 0 ? position / r.durationMs : 0.0;
    final selected = ReplayInfo.speeds.contains(r.speed) ? r.speed : null;
    final speed = SegmentedButton<double>(
      key: ValueKey('$prefix-speed'),
      showSelectedIcon: false,
      emptySelectionAllowed: selected == null,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      segments: [
        for (final s in ReplayInfo.speeds)
          ButtonSegment(
            value: s,
            label: Text(l10n.viewerReviewSpeed(s), key: ValueKey('$prefix-speed-$s')),
            tooltip: l10n.replaySpeed,
          ),
      ],
      selected: {?selected},
      onSelectionChanged: widget.enabled ? (s) => s.isEmpty ? null : widget.onSpeed(s.first) : null,
    );
    final back = FilledButton.icon(
      key: ValueKey('$prefix-stop'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: ReplayBar._onAir,
        foregroundColor: Colors.white,
      ),
      onPressed: widget.enabled ? widget.onStop : null,
      icon: const Icon(Icons.live_tv),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(l10n.replayBackToLive, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
    final header = Row(
      children: [
        const Icon(Icons.fiber_manual_record, size: 14, color: ReplayBar._onAir),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            l10n.replayOnAir,
            key: ValueKey('$prefix-label'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: ReplayBar._onAir, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        Text(
          '${formatReplayTime(position)} / ${formatReplayTime(r.durationMs)}',
          key: ValueKey('$prefix-time'),
          style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3, color: ReplayBar._onAir),
    );
    return Material(
      key: ValueKey(prefix),
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: LayoutBuilder(
          builder: (context, c) {
            // Wide: one row. Narrow (a phone, a side panel): progress on top, controls below.
            if (c.maxWidth >= 560) {
              return Row(
                children: [
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [header, const SizedBox(height: 4), bar]),
                  ),
                  const SizedBox(width: 8),
                  speed,
                  const SizedBox(width: 8),
                  back,
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 2),
                bar,
                const SizedBox(height: 4),
                Row(
                  children: [
                    speed,
                    const SizedBox(width: 4),
                    Expanded(child: back),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

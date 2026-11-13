import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../recording/recording_widgets.dart';
import '../data/session_link.dart';
import '../viewer_providers.dart';

enum CameraProblem { disconnected, notRecording, hot, batteryLow }

/// What the REC indicator shows (UX §3.2): green when recording fine, red with a short warning when
/// something needs action, grey while the first connection is still being made.
@immutable
class CameraHealth {
  const CameraHealth({this.connecting = false, this.problems = const []});

  static const lowBatteryPercent = 20;

  final bool connecting;
  final List<CameraProblem> problems;

  bool get ok => !connecting && problems.isEmpty;

  static CameraHealth of(LinkState? link) {
    if (link == null || link.phase == LinkPhase.connecting) return const CameraHealth(connecting: true);
    if (link.phase != LinkPhase.connected) return const CameraHealth(problems: [CameraProblem.disconnected]);
    final s = link.status;
    if (s == null) return const CameraHealth(connecting: true);
    return CameraHealth(
      problems: [
        if (!s.recording) CameraProblem.notRecording,
        if (s.thermalStatus >= hotThermalStatus) CameraProblem.hot,
        if (s.plugged == false && (s.batteryPercent ?? 100) <= lowBatteryPercent) CameraProblem.batteryLow,
      ],
    );
  }
}

String _problemText(AppLocalizations l10n, CameraProblem p, CameraStatus? s) => switch (p) {
      CameraProblem.disconnected => l10n.viewerProblemDisconnected,
      CameraProblem.notRecording => l10n.viewerStatusIdle,
      CameraProblem.hot => l10n.viewerProblemHot,
      CameraProblem.batteryLow => l10n.viewerProblemBatteryLow(s?.batteryPercent ?? 0),
    };

/// The compact camera-status pill of the top bar: a green dot and `REC` (plus the full
/// recording's clock while it runs), or a red warning when something needs action. Tap for the
/// gauges.
class CameraStatusIndicator extends ConsumerWidget {
  const CameraStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final link = ref.watch(linkStateProvider);
    final health = CameraHealth.of(link);
    final rec = link?.status?.sessionRecording;
    final clock = health.ok && rec != null && rec.state != SessionRecordingState.idle
        ? formatRecordingClock(rec.elapsedMs)
        : null;
    final problem = !health.ok && !health.connecting;
    final (dotColor, text) = health.connecting
        ? (c.muted, l10n.viewerLinkConnecting)
        : health.ok
            ? (c.ok, l10n.viewerStatusRec)
            : (c.live, _problemText(l10n, health.problems.first, link?.status));
    final more = health.problems.length > 1 ? ' +${health.problems.length - 1}' : '';
    final fg = problem ? c.liveText : c.text;
    return Tooltip(
      message: l10n.viewerStatusTitle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: problem ? c.liveSoft : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: problem ? c.live : c.line),
          ),
          child: InkWell(
            key: const ValueKey('viewer-status'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => showCameraStatusSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 48, maxWidth: 170),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (problem)
                      Icon(Icons.warning_rounded, size: 18, color: c.live)
                    else
                      Container(
                        key: const ValueKey('viewer-status-dot'),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          boxShadow: health.ok ? [BoxShadow(color: dotColor.withValues(alpha: 0.7), blurRadius: 8)] : null,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '$text$more',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: health.ok
                            ? irMono(13, weight: FontWeight.w600, color: fg)
                            : TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg),
                      ),
                    ),
                    if (clock != null) ...[
                      const SizedBox(width: 6),
                      Text(clock, key: const ValueKey('viewer-status-clock'), style: irMono(13, weight: FontWeight.w600, color: fg)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showCameraStatusSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => const CameraStatusDetails(),
    );

/// The camera's gauges: battery, temperature, replay buffer, frame rate and pending clips as
/// tiles with a mono value and a thin bar, plus any problem in full and the full recording.
class CameraStatusDetails extends ConsumerWidget {
  const CameraStatusDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final link = ref.watch(linkStateProvider);
    final health = CameraHealth.of(link);
    final s = link?.phase == LinkPhase.connected ? link?.status : null;
    final name = link?.camera?.name;
    final batteryLow = health.problems.contains(CameraProblem.batteryLow);
    final hot = s != null && s.thermalStatus >= hotThermalStatus;
    final gauges = <Widget>[
      if (s != null) ...[
        if (s.batteryPercent case final p?)
          _Gauge(
            icon: s.plugged == true
                ? Icons.battery_charging_full
                : batteryLow
                    ? Icons.battery_alert
                    : Icons.battery_std,
            label: l10n.viewerStatusBatteryLabel,
            value: l10n.viewerStatusBatteryPercent(p),
            detail: switch (s.plugged) {
              true => l10n.viewerStatusCharging,
              false => l10n.viewerStatusNotCharging,
              null => null,
            },
            level: p / 100,
            color: batteryLow ? c.live : (p <= 40 ? c.warn : c.ok),
            alert: batteryLow,
          ),
        _Gauge(
          icon: Icons.thermostat,
          label: l10n.viewerStatusTemperatureLabel,
          value: s.batteryTempC != null
              ? l10n.viewerStatusTemperature(s.batteryTempC!.toStringAsFixed(0))
              : _thermalName(l10n, s.thermalStatus),
          detail: s.batteryTempC != null ? _thermalName(l10n, s.thermalStatus) : null,
          level: ((s.thermalStatus.clamp(0, 6) + 1) / 7).toDouble(),
          color: hot ? c.live : (s.thermalStatus >= 1 ? c.warn : c.ok),
          alert: hot,
        ),
        _Gauge(
          icon: Icons.history,
          label: l10n.viewerStatusBufferLabel,
          value: l10n.viewerStatusSeconds((s.bufferMs / 1000).round()),
          level: (s.bufferMs / 60000).clamp(0, 1).toDouble(),
          color: c.signal,
        ),
        _Gauge(
          icon: Icons.speed,
          label: l10n.viewerStatusFpsLabel,
          value: l10n.viewerStatusFps(s.fps.round()),
          level: (s.fps / 30).clamp(0, 1).toDouble(),
          color: s.fps < 20 ? c.warn : c.ok,
        ),
        _Gauge(
          icon: Icons.fiber_manual_record,
          label: l10n.viewerStatusRecording,
          value: s.recording ? l10n.viewerStatusRec : l10n.viewerStatusIdle,
          color: s.recording ? c.ok : c.live,
          alert: !s.recording,
        ),
        _Gauge(
          icon: Icons.outbox,
          label: l10n.viewerStatusPendingLabel,
          value: '${s.outboxClips}',
        ),
      ],
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.viewerStatusTitle, style: Theme.of(context).textTheme.titleLarge),
            if (name != null) Text(name, style: TextStyle(fontSize: 14, color: c.muted)),
            const SizedBox(height: 12),
            if (health.connecting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(Icons.sync, color: c.muted),
                  const SizedBox(width: 12),
                  Text(l10n.viewerLinkConnecting, style: const TextStyle(fontSize: 16)),
                ]),
              ),
            for (final p in health.problems)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.liveSoft,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: c.live),
                ),
                child: Row(children: [
                  Icon(Icons.warning_rounded, color: c.live),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _problemText(l10n, p, s),
                      style: TextStyle(color: c.liveText, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ]),
              ),
            if (gauges.isNotEmpty)
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth >= 480 ? 3 : 2;
                final width = (box.maxWidth - 8 * (columns - 1)) / columns;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in gauges) SizedBox(width: width, child: g),
                ]);
              }),
            // Longer than the other values: a full-width tile.
            if (s?.sessionRecording case final r?) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: r.lowSpace ? c.live : c.line),
                ),
                child: Row(children: [
                  Icon(Icons.videocam, color: r.lowSpace ? c.live : c.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l10n.recTitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
                      Text(
                        [
                          switch (r.state) {
                            SessionRecordingState.idle => l10n.recIdle,
                            SessionRecordingState.recording => formatRecordingClock(r.elapsedMs),
                            SessionRecordingState.paused => l10n.recPaused(formatRecordingClock(r.elapsedMs)),
                          },
                          if (r.remainingMs case final left?)
                            r.lowSpace ? l10n.recLowSpace(formatRecordingSpan(left)) : l10n.recRemaining(formatRecordingSpan(left)),
                        ].join(' · '),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: r.lowSpace ? c.liveText : c.text),
                      ),
                    ]),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _thermalName(AppLocalizations l10n, int status) => switch (status) {
        <= 0 => l10n.thermalNone,
        1 => l10n.thermalLight,
        2 => l10n.thermalModerate,
        3 => l10n.thermalSevere,
        4 => l10n.thermalCritical,
        5 => l10n.thermalEmergency,
        _ => l10n.thermalShutdown,
      };
}

/// One gauge tile: label, a big mono value, an optional detail and a thin level bar.
class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.level,
    this.color,
    this.alert = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  /// 0–1; null draws no bar.
  final double? level;
  final Color? color;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: alert ? c.live : c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: alert ? c.live : c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value, maxLines: 1, style: irMono(22, color: alert ? c.liveText : c.text)),
        ),
        if (detail != null)
          Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: c.line),
              if (level != null)
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: level!.clamp(0, 1).toDouble(),
                  child: ColoredBox(color: color ?? c.signal),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

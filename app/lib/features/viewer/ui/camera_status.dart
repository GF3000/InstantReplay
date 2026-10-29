import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../l10n/app_localizations.dart';
import '../data/session_link.dart';
import '../viewer_providers.dart';

enum CameraProblem { disconnected, notRecording, hot, batteryLow }

/// What the REC indicator shows (UX §3.2): green when recording fine, red with a short warning when
/// something needs action, grey while the first connection is still being made.
@immutable
class CameraHealth {
  const CameraHealth({this.connecting = false, this.problems = const []});

  static const hotThermalStatus = 3;
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

/// The REC dot for the app bar. Tap for details.
class CameraStatusIndicator extends ConsumerWidget {
  const CameraStatusIndicator({super.key});

  static const okColor = Color(0xFF43A047);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final link = ref.watch(linkStateProvider);
    final health = CameraHealth.of(link);
    final (color, text) = health.connecting
        ? (scheme.outline, l10n.viewerLinkConnecting)
        : health.ok
            ? (okColor, l10n.viewerStatusRec)
            : (scheme.error, _problemText(l10n, health.problems.first, link?.status));
    final more = health.problems.length > 1 ? ' +${health.problems.length - 1}' : '';
    return Tooltip(
      message: l10n.viewerStatusTitle,
      child: InkWell(
        key: const ValueKey('viewer-status'),
        borderRadius: BorderRadius.circular(24),
        onTap: () => showCameraStatusSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, maxWidth: 200),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(health.ok ? Icons.fiber_manual_record : Icons.warning_rounded, size: 18, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$text$more',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, color: health.ok ? null : color),
                  ),
                ),
              ],
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
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => const CameraStatusDetails(),
    );

/// fps, buffer, pending clips, temperature and battery, plus any problem in full.
class CameraStatusDetails extends ConsumerWidget {
  const CameraStatusDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final link = ref.watch(linkStateProvider);
    final health = CameraHealth.of(link);
    final s = link?.phase == LinkPhase.connected ? link?.status : null;
    Widget row(IconData icon, String label, String value, {bool alert = false}) => ListTile(
          dense: true,
          leading: Icon(icon, color: alert ? scheme.error : null),
          title: Text(label),
          trailing: Text(value, style: TextStyle(fontSize: 16, color: alert ? scheme.error : null)),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.viewerStatusTitle, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (health.connecting) ListTile(leading: const Icon(Icons.sync), title: Text(l10n.viewerLinkConnecting)),
            for (final p in health.problems)
              ListTile(
                leading: Icon(Icons.warning_rounded, color: scheme.error),
                title: Text(
                  _problemText(l10n, p, s),
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold),
                ),
              ),
            if (s != null) ...[
              row(
                Icons.fiber_manual_record,
                l10n.viewerStatusRecording,
                s.recording ? l10n.viewerStatusRec : l10n.viewerStatusIdle,
                alert: !s.recording,
              ),
              row(Icons.speed, l10n.viewerStatusFpsLabel, l10n.viewerStatusFps(s.fps.round())),
              row(Icons.history, l10n.viewerStatusBufferLabel, l10n.viewerStatusSeconds((s.bufferMs / 1000).round())),
              row(Icons.outbox, l10n.viewerStatusPendingLabel, '${s.outboxClips}'),
              row(
                Icons.thermostat,
                l10n.viewerStatusTemperatureLabel,
                [
                  if (s.batteryTempC case final t?) l10n.viewerStatusTemperature(t.toStringAsFixed(0)),
                  _thermalName(l10n, s.thermalStatus),
                ].join(' · '),
                alert: s.thermalStatus >= CameraHealth.hotThermalStatus,
              ),
              if (s.batteryPercent case final p?)
                row(
                  s.plugged == true
                      ? Icons.battery_charging_full
                      : health.problems.contains(CameraProblem.batteryLow)
                          ? Icons.battery_alert
                          : Icons.battery_std,
                  l10n.viewerStatusBatteryLabel,
                  [
                    l10n.viewerStatusBatteryPercent(p),
                    if (s.plugged case final plugged?)
                      plugged ? l10n.viewerStatusCharging : l10n.viewerStatusNotCharging,
                  ].join(' · '),
                  alert: health.problems.contains(CameraProblem.batteryLow),
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

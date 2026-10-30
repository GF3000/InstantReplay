import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:replay_capture_android/replay_capture_android.dart';
import 'package:replay_protocol/replay_protocol.dart' show RecordingEndReason, hotThermalStatus;

import '../../core/orientation_lock.dart';
import '../../l10n/app_localizations.dart';
import '../recording/recording_widgets.dart';
import '../role/role.dart';
import '../server/protocol_mapping.dart' show sessionRecording;
import '../server/server_controller.dart';
import 'camera_session.dart';
import 'pairing_card.dart';

/// Camera role (SPEC §3.5, D17; UX §2): a setup screen to frame the shot and pair a viewer, and a
/// black operating mode that starts by itself when the first viewer connects.
/// Capture starts on entry and stops when this screen goes away.
class CameraPage extends ConsumerWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operating = ref.watch(cameraSessionProvider.select((s) => s.operating));
    // Keeps the API server alive across the setup/operating switch; it stops with this screen.
    ref.listen(cameraServerProvider, (_, _) {});
    // UX §2.2: going from no viewers to one turns the screen black. Waking to setup while viewers
    // stay connected is respected; so is a recent wake, because a viewer whose phone locks or loses
    // Wi-Fi reconnects (0 → 1) and must not blank the screen while the coach is reframing.
    ref.listen(cameraServerProvider.select((s) => s.viewers), (previous, viewers) {
      if ((previous ?? 0) > 0 || viewers == 0) return;
      final session = ref.read(cameraSessionProvider.notifier);
      if (ref.read(cameraSessionProvider).phase != CameraPhase.running) return;
      final woken = session.lastWokenAt;
      if (woken != null && DateTime.now().difference(woken) < autoOperatingQuietPeriod) return;
      session.startOperating();
    });
    // A recording ended (by anyone: this screen, a viewer, low space or an error): say so here too.
    ref.listen(cameraSessionProvider.select((s) => s.lastSaved), (_, notice) {
      if (notice == null) return;
      final saved = notice.saved;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(recordingSavedMessage(
          l10n,
          parts: saved.parts,
          durationMs: saved.durationMs,
          reason: RecordingEndReason.values.byName(saved.reason.name),
        )),
      ));
    });
    return OrientationLock(child: operating ? const _OperatingView() : const _SetupView());
  }
}

// region Setup mode

class _SetupView extends ConsumerWidget {
  const _SetupView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraSessionProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final preview = _Preview(state: state);
          final panel = _Panel(state: state);
          // Portrait only before the landscape lock applies; keep it usable anyway.
          if (c.maxHeight > c.maxWidth) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: c.maxHeight * 0.4, child: preview),
              Expanded(child: panel),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: preview),
            SizedBox(width: (c.maxWidth * 0.45).clamp(300.0, 420.0), child: panel),
          ]);
        }),
      ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final session = state.session;
    if (session != null) {
      final profile = state.profile;
      final aspect = profile == null || profile.height == 0 ? 16 / 9 : profile.width / profile.height;
      return Stack(children: [
        Center(child: AspectRatio(aspectRatio: aspect, child: Texture(textureId: session.textureId))),
        // The full-session recording rides on the preview, so the pairing panel keeps its room.
        PositionedDirectional(
          start: 8,
          top: 8,
          end: 8,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _CameraRecording(state: state),
            ),
          ),
        ),
        // The manual way in; the first viewer also starts operating mode by itself (UX §2.2).
        PositionedDirectional(
          start: 12,
          bottom: 12,
          child: FilledButton.icon(
            icon: const Icon(Icons.dark_mode),
            label: Text(l10n.cameraStartOperating),
            onPressed: state.phase == CameraPhase.running
                ? () => ref.read(cameraSessionProvider.notifier).startOperating()
                : null,
          ),
        ),
      ]);
    }

    Widget message(String text, {bool retry = true}) => _Message(text: text, retry: retry);
    return switch (state.phase) {
      CameraPhase.initializing || CameraPhase.starting || CameraPhase.running => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.cameraStarting, style: text.titleMedium),
          ]),
        ),
      CameraPhase.permissionDenied => message(l10n.cameraPermissionDenied),
      CameraPhase.noProfiles => message(l10n.cameraNoProfiles, retry: false),
      CameraPhase.startFailed => message(l10n.cameraStartFailed(state.startError ?? '')),
    };
  }
}

class _Message extends ConsumerWidget {
  const _Message({required this.text, required this.retry});

  final String text;
  final bool retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(text, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).cameraRetry),
              onPressed: () => ref.read(cameraSessionProvider.notifier).enter(),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Pairing first, warnings only when they need action, everything technical under "Advanced".
class _Panel extends ConsumerWidget {
  const _Panel({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(cameraSessionProvider.notifier);
    final stats = state.stats;
    final thermal = state.thermalStatus;

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Row(children: [
            Expanded(child: Text(l10n.roleCamera, style: theme.textTheme.titleLarge)),
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: l10n.switchRole,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: () async {
                await ref.read(roleProvider.notifier).clear();
                if (context.mounted) context.go('/');
              },
            ),
          ]),
          // Pairing first: it is what the coach needs while mounting, even with warnings below it.
          const PairingCard(),
          const SizedBox(height: 8),
          if (state.errors.isNotEmpty) ...[
            _ErrorCard(errors: state.errors, onDismiss: notifier.dismissErrors),
            const SizedBox(height: 8),
          ],
          if (thermal != null && thermal >= _thermalModerate)
            _Warning(Icons.thermostat, l10n.cameraHotWarning(thermalName(l10n, thermal)), error: true),
          if (stats != null && !stats.plugged) _Warning(Icons.power_off, l10n.cameraNotChargingWarning),
          if (state.notificationsDenied) _Warning(Icons.notifications_off, l10n.cameraNotificationsDenied),
          if (state.recovered.isNotEmpty) ...[
            _RecoveredCard(recovered: state.recovered, onDismiss: notifier.dismissRecovered),
            const SizedBox(height: 8),
          ],
          _Advanced(state: state),
        ],
      ),
    );
  }
}

/// The Camera's own Record / Pause / Finish (SPEC §3.8), the same controls every viewer has.
class _CameraRecording extends ConsumerWidget {
  const _CameraRecording({required this.state, this.dim = false});

  final CameraSessionState state;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cameraSessionProvider.notifier);
    final bar = RecordingBar(
      key: const Key('camera-recording'),
      recording: switch (state.recording) {
        final r? => sessionRecording(r),
        null => null,
      },
      enabled: state.phase == CameraPhase.running,
      keyPrefix: 'camera-rec',
      buttonSize: 56,
      dim: dim,
      onRecord: (seconds) => _run(context, () => notifier.recordStart(includeSeconds: seconds)),
      onPause: () => _run(context, notifier.recordPause),
      onFinish: () => _run(context, notifier.recordStop),
    );
    if (dim) return bar;
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.85),
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 4, 4), child: bar),
    );
  }

  static Future<void> _run(BuildContext context, Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(recordingErrorMessage(l10n, e.code, e.message))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.recFailed('$e'))));
    }
  }
}

/// «Se ha recuperado una grabación de 47 min»: recordings a crash left open, finished on entry.
class _RecoveredCard extends StatelessWidget {
  const _RecoveredCard({required this.recovered, required this.onDismiss});

  final List<RecordingSaved> recovered;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onTertiaryContainer);
    return Card(
      key: const Key('camera-recovered'),
      color: scheme.tertiaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in recovered)
            Row(children: [
              Icon(Icons.restore, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.recRecovered(formatRecordingSpan(r.durationMs)),
                  style: style.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ]),
          const SizedBox(height: 4),
          Text(l10n.recRecoveredHint, style: style),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.onTertiaryContainer, minimumSize: const Size(56, 56)),
              onPressed: onDismiss,
              child: Text(l10n.cameraDismissErrors),
            ),
          ),
        ]),
      ),
    );
  }
}

/// UX §2.1: quality profile, live statistics, diagnostics and the test save, collapsed by default.
class _Advanced extends ConsumerWidget {
  const _Advanced({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(cameraSessionProvider.notifier);
    final stats = state.stats;
    final running = state.phase == CameraPhase.running;

    return ExpansionTile(
      key: const Key('camera-advanced'),
      leading: const Icon(Icons.tune),
      title: Text(l10n.cameraAdvanced),
      minTileHeight: 56,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.profiles.isNotEmpty) ...[
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.cameraProfile,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('camera-profile'),
                value: state.profileId,
                isExpanded: true,
                itemHeight: 56,
                items: [
                  for (final p in state.profiles) DropdownMenuItem(value: p.id, child: Text(_profileLabel(p))),
                ],
                onChanged: state.phase == CameraPhase.starting || state.phase == CameraPhase.initializing
                    ? null
                    : (id) => id == null ? null : notifier.selectProfile(id),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (state.cameraState != null) _StatRow(l10n.cameraStatCamera, state.cameraState!),
        if (stats == null)
          Text(l10n.cameraWaitingForStats, style: theme.textTheme.bodyMedium)
        else ...[
          _StatRow(l10n.cameraStatFps, l10n.cameraFpsValue(stats.fps.toStringAsFixed(1))),
          _StatRow(
            l10n.cameraStatGaps,
            l10n.cameraGapsValue(stats.gaps, stats.cameraGaps, stats.glGaps),
            alert: stats.gaps > 0,
          ),
          _StatRow(l10n.cameraStatBuffer, l10n.cameraBufferValue(stats.bufferMs ~/ 1000, _mb(stats.bufferBytes))),
          _StatRow(l10n.cameraStatOutbox, l10n.cameraOutboxValue(stats.outboxClips, _mb(stats.outboxBytes))),
          _StatRow(
            l10n.cameraStatBattery,
            l10n.cameraBatteryValue(
              _temperature(stats.batteryTempC),
              stats.batteryPercent == null ? '–' : '${stats.batteryPercent} %',
              stats.plugged ? l10n.cameraCharging : l10n.cameraNotCharging,
            ),
          ),
        ],
        if (state.thermalStatus != null)
          _StatRow(
            l10n.cameraStatThermal,
            thermalName(l10n, state.thermalStatus!),
            alert: state.thermalStatus! >= _thermalModerate,
          ),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.save_alt),
            label: Text(l10n.cameraSaveTestClip),
            onPressed: running ? () => _saveTestClip(context, notifier) : null,
          ),
        ],
      ],
    );
  }

  Future<void> _saveTestClip(BuildContext context, CameraSessionNotifier notifier) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final clip = await notifier.saveTestClip();
      message = l10n.cameraTestClipSaved(((clip.durationMs ?? 0) / 1000).toStringAsFixed(1), _mb(clip.bytes ?? 0));
    } catch (e) {
      message = l10n.cameraTestClipFailed(e is PlatformException ? (e.message ?? e.code) : '$e');
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  static String _profileLabel(CaptureProfile p) =>
      '${p.height}p${p.fps} · ${(p.bitrate / 1e6).toStringAsFixed(0)} Mbps';
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.errors, required this.onDismiss});

  final List<String> errors;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onErrorContainer);
    return Card(
      color: scheme.errorContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.error, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Text(l10n.cameraErrorsTitle, style: style.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          for (final e in errors)
            Padding(padding: const EdgeInsets.only(bottom: 4, right: 8), child: Text(e, style: style)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer, minimumSize: const Size(56, 56)),
              onPressed: onDismiss,
              child: Text(l10n.cameraDismissErrors),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One compact line: what needs attention, in amber (or red for errors).
class _Warning extends StatelessWidget {
  const _Warning(this.icon, this.text, {this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, {this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 116, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: alert ? scheme.error : scheme.onSurface, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}

// endregion

// region Operating mode

/// Pure black with one dim status line, so an AMOLED screen draws almost nothing. Tap to wake.
class _OperatingView extends ConsumerStatefulWidget {
  const _OperatingView();

  @override
  ConsumerState<_OperatingView> createState() => _OperatingViewState();
}

class _OperatingViewState extends ConsumerState<_OperatingView> {
  static const _dim = Color(0xFF5A5A5A);
  static const _dimRed = Color(0xFF8A2A2A);
  static const _style = TextStyle(color: _dim, fontSize: 14);
  static const _styleRed = TextStyle(color: _dimRed, fontSize: 14);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(cameraSessionProvider);
    final stats = state.stats;
    final running = state.phase == CameraPhase.running;
    final hot = (state.thermalStatus ?? 0) >= _thermalModerate;
    final viewers = ref.watch(cameraServerProvider.select((s) => s.viewers));

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const Key('camera-operating'),
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(cameraSessionProvider.notifier).stopOperating(),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                // The recording stays at hand without waking the screen; the buttons take their
                // own taps, everything around them wakes to setup.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _CameraRecording(state: state, dim: true),
                ),
                const SizedBox(height: 12),
                for (final r in state.recovered)
                  Text(l10n.recRecovered(formatRecordingSpan(r.durationMs)), style: _style),
                for (final e in state.errors.take(2))
                  Text(e, style: _styleRed),
                // A Wrap, not a Row: the line must never overflow on a small landscape phone.
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Icon(Icons.circle, size: 10, color: running ? _dimRed : _dim),
                  Text(
                    l10n.cameraOperatingStatus(
                      (stats?.bufferMs ?? 0) ~/ 1000,
                      stats?.outboxClips ?? 0,
                      _temperature(stats?.batteryTempC),
                    ),
                    style: _style,
                  ),
                  const Icon(Icons.people, size: 14, color: _dim),
                  Text(l10n.cameraOperatingViewers(viewers), style: _style),
                  if (hot) ...[
                    const Icon(Icons.thermostat, size: 14, color: _dimRed),
                    Text(thermalName(l10n, state.thermalStatus!), style: _styleRed),
                  ],
                  if (stats != null && !stats.plugged) ...[
                    const Icon(Icons.power_off, size: 14, color: _dimRed),
                    Text(l10n.cameraNotCharging, style: _styleRed),
                  ],
                ]),
                Text(l10n.cameraOperatingHint, style: const TextStyle(color: Color(0xFF303030), fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// endregion

/// `PowerManager.THERMAL_STATUS_MODERATE`: the first level that degrades capture (SPEC §3.6).
/// After a manual wake, a viewer (re)connecting does not switch to operating mode for this long.
const autoOperatingQuietPeriod = Duration(minutes: 2);

const _thermalModerate = hotThermalStatus;

String thermalName(AppLocalizations l10n, int status) => switch (status) {
      <= 0 => l10n.thermalNone,
      1 => l10n.thermalLight,
      2 => l10n.thermalModerate,
      3 => l10n.thermalSevere,
      4 => l10n.thermalCritical,
      5 => l10n.thermalEmergency,
      _ => l10n.thermalShutdown,
    };

String _mb(int bytes) => (bytes / 1e6).toStringAsFixed(0);

String _temperature(double? celsius) => celsius == null ? '–' : '${celsius.toStringAsFixed(1)} °C';

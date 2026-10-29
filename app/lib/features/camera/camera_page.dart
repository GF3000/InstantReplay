import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

import '../../core/orientation_lock.dart';
import '../../l10n/app_localizations.dart';
import '../role/role.dart';
import 'camera_session.dart';

/// Camera role (SPEC §3.5, D17): setup mode with preview and status, and a black operating mode.
/// Capture starts on entry and stops when this screen goes away.
class CameraPage extends ConsumerWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operating = ref.watch(cameraSessionProvider.select((s) => s.operating));
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Preview(state: state)),
            SizedBox(width: 360, child: _Panel(state: state)),
          ],
        ),
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
      return Center(
        child: AspectRatio(aspectRatio: aspect, child: Texture(textureId: session.textureId)),
      );
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

class _Panel extends ConsumerWidget {
  const _Panel({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(cameraSessionProvider.notifier);
    final stats = state.stats;
    final running = state.phase == CameraPhase.running;

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
          if (state.errors.isNotEmpty) ...[
            _ErrorCard(errors: state.errors, onDismiss: notifier.dismissErrors),
            const SizedBox(height: 12),
          ],
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
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.dark_mode),
            label: Text(l10n.cameraStartOperating),
            onPressed: running ? notifier.startOperating : null,
          ),
          if (stats != null && !stats.plugged) _Warning(l10n.cameraNotChargingWarning),
          if (state.notificationsDenied) _Warning(l10n.cameraNotificationsDenied),
          const Divider(height: 24),
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
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              icon: const Icon(Icons.save_alt),
              label: Text(l10n.cameraSaveTestClip),
              onPressed: running ? () => _saveTestClip(context, notifier) : null,
            ),
          ],
        ],
      ),
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

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
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
        SizedBox(width: 130, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
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
                for (final e in state.errors.take(2))
                  Text(e, style: const TextStyle(color: _dimRed, fontSize: 14)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 10, color: running ? _dimRed : _dim),
                  const SizedBox(width: 8),
                  Text(
                    l10n.cameraOperatingStatus(
                      (stats?.bufferMs ?? 0) ~/ 1000,
                      stats?.outboxClips ?? 0,
                      _temperature(stats?.batteryTempC),
                    ),
                    style: const TextStyle(color: _dim, fontSize: 14),
                  ),
                  if (hot) ...[
                    const SizedBox(width: 8),
                    Text(thermalName(l10n, state.thermalStatus!), style: const TextStyle(color: _dimRed, fontSize: 14)),
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
const _thermalModerate = 2;

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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:replay_capture_android/replay_capture_android.dart';
import 'package:replay_protocol/replay_protocol.dart'
    show
        BroadcastInfo,
        BroadcastStreamState,
        RecordingEndReason,
        ReplayInfo,
        ScoreboardState,
        SettingsCommand,
        formatClock,
        hotThermalStatus;

import '../../core/orientation_lock.dart';
import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../broadcast/broadcast_controller.dart';
import '../broadcast/broadcast_host.dart';
import '../broadcast/broadcast_providers.dart';
import '../broadcast/broadcast_widgets.dart';
import '../broadcast/replay_widgets.dart';
import '../broadcast/scoreboard_controller.dart' show periodLabel;
import '../recording/recording_widgets.dart';
import '../role/confirm_switch_role.dart';
import '../role/role.dart';
import '../server/protocol_mapping.dart' show sessionRecording;
import '../server/server_controller.dart';
import 'camera_session.dart';
import 'broadcast_checklist.dart';
import 'clip_reserve_widgets.dart';
import 'pairing_card.dart';
import 'zoom_widgets.dart';
import '../broadcast/youtube/youtube_account.dart';
import '../broadcast/youtube/youtube_providers.dart';

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

/// A phone on its side: the broadcasting screen packs its controls tighter (B2_CamaraMovil).
bool _compact(BuildContext context) => MediaQuery.sizeOf(context).height < 600;

// region Setup mode

class _SetupView extends ConsumerWidget {
  const _SetupView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraSessionProvider);
    final c = context.ir;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final broadcast = state.broadcast;
          final panel = broadcast ? _BroadcastPanel(state: state) : _SetupPanel(state: state);
          // Portrait only before the landscape lock applies; keep it usable anyway.
          if (box.maxHeight > box.maxWidth) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: box.maxHeight * (broadcast ? 0.3 : 0.4), child: _Preview(state: state)),
              if (broadcast)
                ColoredBox(
                  color: c.surface,
                  child: Padding(padding: const EdgeInsets.all(8), child: _CameraScoreboardControls(state: state, compact: true)),
                ),
              Expanded(child: panel),
            ]);
          }
          final panelWidth = broadcast
              ? (box.maxWidth * 0.34).clamp(220.0, 360.0)
              : (box.maxWidth * 0.45).clamp(300.0, 420.0);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: broadcast ? _BroadcastStage(state: state) : _Preview(state: state)),
            VerticalDivider(width: 1, color: c.line),
            SizedBox(width: panelWidth, child: panel),
          ]);
        }),
      ),
    );
  }
}

/// Broadcast mode, left side: what YouTube sees, and the scoreboard strip under it, always there.
class _BroadcastStage extends StatelessWidget {
  const _BroadcastStage({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < 600;
      final stripMin = compact ? 92.0 : 170.0;
      final previewHeight = (box.maxWidth * 9 / 16).clamp(0.0, (box.maxHeight - stripMin).clamp(80.0, double.infinity));
      // No caption on the picture: the burned-in scoreboard sits top-left and must stay visible.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: previewHeight, child: _Preview(state: state)),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 20, vertical: compact ? 6 : 12),
                child: _CameraScoreboardControls(state: state, compact: compact),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final session = state.session;
    if (session != null) {
      final profile = state.profile;
      final aspect = profile == null || profile.height == 0 ? 16 / 9 : profile.width / profile.height;
      final notifier = ref.read(cameraSessionProvider.notifier);
      final running = state.phase == CameraPhase.running;
      final zoomable = state.maxZoom > 1;
      final silent = state.broadcast && !(ref.watch(broadcastInfoProvider).value?.audio ?? true);
      Widget badge(String text, {Color? bg, Color? fg}) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: bg ?? Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(2)),
            child: Text(text, style: irMono(11, weight: FontWeight.w600, color: fg ?? Colors.white)),
          );
      return ColoredBox(
        color: Colors.black,
        child: Stack(children: [
          Positioned.fill(
            child: ZoomPinch(
              ratio: state.zoom,
              max: state.maxZoom,
              enabled: running && zoomable,
              onChanged: notifier.setZoom,
              child: Center(child: AspectRatio(aspectRatio: aspect, child: Texture(textureId: session.textureId))),
            ),
          ),
          if (zoomable)
            PositionedDirectional(
              end: 8,
              bottom: 8,
              child: ZoomControl(
                keyPrefix: 'camera-zoom',
                ratio: state.zoom,
                max: state.maxZoom,
                enabled: running,
                onChanged: notifier.setZoom,
              ),
            ),
          // The full-session recording rides on the preview, so the panel keeps its room.
          PositionedDirectional(
            start: 8,
            top: 8,
            end: 8,
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: _CameraRecording(state: state),
            ),
          ),
          // Bottom-left: the burned-in scoreboard is top-left and the zoom bottom-right.
          if (silent)
            PositionedDirectional(
              start: 8,
              bottom: 8,
              child: badge(l10n.camNoSound, bg: c.live, fg: c.onLive),
            ),
          // The manual way in; the first viewer also starts operating mode by itself (UX §2.2).
          // In broadcast mode it sits in the panel.
          if (!state.broadcast)
            PositionedDirectional(
              start: 12,
              bottom: 12,
              child: _BlackScreenButton(state: state),
            ),
        ]),
      );
    }

    Widget message(String text, {bool retry = true}) => _Message(text: text, retry: retry);
    return switch (state.phase) {
      CameraPhase.initializing || CameraPhase.starting || CameraPhase.running => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.cameraStarting, style: TextStyle(fontSize: 16, color: c.text)),
          ]),
        ),
      CameraPhase.permissionDenied => message(l10n.cameraPermissionDenied),
      CameraPhase.noProfiles => message(l10n.cameraNoProfiles, retry: false),
      CameraPhase.startFailed => message(l10n.cameraStartFailed(state.startError ?? '')),
    };
  }
}

/// Turns the screen black (operating mode).
class _BlackScreenButton extends ConsumerWidget {
  const _BlackScreenButton({required this.state, this.expand = false});

  final CameraSessionState state;
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return SizedBox(height: 48, child: IrKey(
      key: const Key('camera-black-screen'),
      minHeight: 48,
      onPressed: state.phase == CameraPhase.running ? () => ref.read(cameraSessionProvider.notifier).startOperating() : null,
      child: Center(child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.dark_mode, size: 20, color: c.text),
        const SizedBox(width: 8),
        Flexible(
          child: Text(state.broadcast ? l10n.camBlackScreen : l10n.cameraStartOperating,
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        ),
      ])),
    ));
  }
}

class _Message extends ConsumerWidget {
  const _Message({required this.text, required this.retry});

  final String text;
  final bool retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ir;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off, size: 56, color: c.liveText),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text), textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 24),
            SizedBox(height: 56, child: IrKey(
              onPressed: () => ref.read(cameraSessionProvider.notifier).enter(),
              led: c.signal,
              child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh, color: c.text),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context).cameraRetry,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
              ])),
            )),
          ],
        ]),
      ),
    );
  }
}

/// The panel title row: a title, an optional line under it, and the icon buttons on the right.
class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.state, required this.title, this.subtitle, this.actions = const []});

  final CameraSessionState state;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.1, color: c.text)),
            if (subtitle != null)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.muted)),
          ]),
        ),
        ...actions,
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: l10n.switchRole,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () async {
            // Switching role stops capture, the stream and every viewer's connection.
            final info = state.broadcast ? ref.read(broadcastControllerProvider).info : null;
            final onAir = info?.active ?? false;
            final viewers = ref.read(cameraServerProvider).viewers;
            if ((onAir || viewers > 0) &&
                !await confirmSwitchRole(
                  context,
                  onAir ? l10n.switchRoleBroadcastBody : l10n.switchRoleViewersBody(viewers),
                )) {
              return;
            }
            await ref.read(roleProvider.notifier).clear();
            if (context.mounted) context.go('/');
          },
        ),
      ]),
    );
  }
}

/// Replay mode (the Camera role): pairing first, warnings only when they need action, everything
/// technical under "Advanced".
class _SetupPanel extends ConsumerWidget {
  const _SetupPanel({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        _PanelHeader(state: state, title: l10n.roleCamera),
        // Pairing first: it is what the coach needs while mounting, even with warnings below it.
        const PairingCard(),
        const SizedBox(height: 8),
        ..._notices(context, ref, state),
        _Advanced(state: state),
      ],
    );
  }
}

/// Errors, warnings and recovered recordings: shown while they need attention.
List<Widget> _notices(BuildContext context, WidgetRef ref, CameraSessionState state) {
  final l10n = AppLocalizations.of(context);
  final notifier = ref.read(cameraSessionProvider.notifier);
  final stats = state.stats;
  final thermal = state.thermalStatus;
  return [
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
  ];
}

/// The Camera's own Record / Pause / Finish (SPEC §3.8), the same controls every viewer has.
class _CameraRecording extends ConsumerWidget {
  const _CameraRecording({required this.state, this.dim = false});

  final CameraSessionState state;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cameraSessionProvider.notifier);
    // A small button, not a bar: recording the whole session is set up once, not used all match.
    return RecordingButton(
      key: const Key('camera-recording'),
      recording: switch (state.recording) {
        final r? => sessionRecording(r),
        null => null,
      },
      enabled: state.phase == CameraPhase.running,
      keyPrefix: 'camera-rec',
      dim: dim,
      overVideo: !dim,
      onRecord: (seconds) => _run(context, () => notifier.recordStart(includeSeconds: seconds)),
      onPause: () => _run(context, notifier.recordPause),
      onFinish: () => _run(context, notifier.recordStop),
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
    final c = context.ir;
    return IrPanel(
      key: const Key('camera-recovered'),
      borderColor: c.info,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in recovered)
          Row(children: [
            Icon(Icons.restore, color: c.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.recRecovered(formatRecordingSpan(r.durationMs)),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c.text),
              ),
            ),
          ]),
        const SizedBox(height: 4),
        Text(l10n.recRecoveredHint, style: TextStyle(fontSize: 14, color: c.muted)),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(56, 48)),
            onPressed: onDismiss,
            child: Text(l10n.cameraDismissErrors),
          ),
        ),
      ]),
    );
  }
}

/// UX §2.1: quality profile, live statistics, diagnostics and the test save, collapsed by default.
class _Advanced extends ConsumerStatefulWidget {
  const _Advanced({required this.state});

  final CameraSessionState state;

  @override
  ConsumerState<_Advanced> createState() => _AdvancedState();
}

class _AdvancedState extends ConsumerState<_Advanced> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final state = widget.state;
    final notifier = ref.read(cameraSessionProvider.notifier);
    final stats = state.stats;
    final running = state.phase == CameraPhase.running;

    return IrPanel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: const Key('camera-advanced'),
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(Icons.tune, color: c.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.cameraAdvanced, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: c.muted),
              ]),
            ),
          ),
        ),
        if (_open)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Replays on air exist only in broadcast mode, and so does their reserve.
              if (state.broadcast) ...[
                ClipReserveStepper(
                  keyPrefix: 'camera-clip-reserve',
                  size: state.clipReserve,
                  max: CameraSessionNotifier.maxClipReserve,
                  enabled: true,
                  onChanged: notifier.setClipReserve,
                ),
                const SizedBox(height: 12),
              ],
              if (state.profiles.isNotEmpty) ...[
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.cameraProfile,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('camera-profile'),
                      value: state.profileId,
                      isExpanded: true,
                      itemHeight: 56,
                      items: [
                        for (final p in state.profiles) DropdownMenuItem(value: p.id, child: Text(_profileLabel(context, p))),
                      ],
                      onChanged: state.phase == CameraPhase.starting ||
                              state.phase == CameraPhase.initializing ||
                              _streaming(ref)
                          ? null
                          : (id) => id == null ? null : notifier.selectProfile(id),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (state.cameraState != null) _StatRow(l10n.cameraStatCamera, state.cameraState!),
              if (stats == null)
                Text(l10n.cameraWaitingForStats, style: TextStyle(color: c.muted))
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
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.save_alt),
                  label: Text(l10n.cameraSaveTestClip),
                  onPressed: running ? () => _saveTestClip(context, notifier) : null,
                ),
              ],
            ]),
          ),
      ]),
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

  /// "1080p30 · 8 Mbps · 3.6 GB/h": the storage per hour helps to pick a bitrate.
  static String _profileLabel(BuildContext context, CaptureProfile p) {
    final gbPerHour = NumberFormat('0.0', Localizations.localeOf(context).toString()).format(p.bitrate * 3600 / 8 / 1e9);
    return '${p.height}p${p.fps} · ${(p.bitrate / 1e6).toStringAsFixed(0)} Mbps · $gbPerHour GB/h';
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.errors, required this.onDismiss});

  final List<String> errors;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return IrPanel(
      color: c.liveSoft,
      borderColor: c.live,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error, color: c.liveText),
          const SizedBox(width: 8),
          Text(l10n.cameraErrorsTitle, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c.liveText)),
        ]),
        const SizedBox(height: 8),
        for (final e in errors)
          Padding(padding: const EdgeInsets.only(bottom: 4, right: 8), child: Text(e, style: TextStyle(color: c.text))),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: c.liveText, minimumSize: const Size(56, 48)),
            onPressed: onDismiss,
            child: Text(l10n.cameraDismissErrors),
          ),
        ),
      ]),
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
    final c = context.ir;
    final color = error ? c.liveText : c.warnText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: color))),
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
    final c = context.ir;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 116, child: Text(label, style: TextStyle(color: c.muted))),
        Expanded(
          child: Text(value, style: TextStyle(color: alert ? c.liveText : c.text, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A small status tile: a label over a figure (battery, temperature, memory, viewers).
class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return IrPanel(
      color: c.bg,
      borderColor: alert ? c.warn : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
        Text(value, maxLines: 1, style: irMono(20, color: alert ? c.warnText : c.text)),
      ]),
    );
  }
}

// endregion

// region Broadcast mode (SPEC §12)

/// A stream is starting, on air or reconnecting: changing the mode or the profile would cut it.
bool _streaming(WidgetRef ref) =>
    ref.watch(cameraSessionProvider.select((s) => s.broadcast)) &&
    (ref.watch(broadcastInfoProvider).value?.active ?? false);

/// Broadcast mode, right side (B2_Camara / B2_CamaraMovil): the stream (Go live, or on air with
/// Stop), the microphone, the checklist, the status tiles, connecting a viewer, sharing the live,
/// the black screen; then notices and Advanced.
class _BroadcastPanel extends ConsumerWidget {
  const _BroadcastPanel({required this.state});

  final CameraSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final compact = _compact(context);
    final running = state.phase == CameraPhase.running;
    final controller = ref.watch(broadcastControllerProvider);
    final info = ref.watch(broadcastInfoProvider).value ?? controller.info;
    final replay = ref.watch(replayInfoProvider).value;
    final server = ref.watch(cameraServerProvider);
    final youtube = ref.watch(youtubeActiveAccountProvider).value;
    if (youtube != null) {
      // Ask YouTube for the live's link now, so "Share the live" opens at once (no-op when known).
      final title = youtubeDefaultTitle(l10n, DateTime.now());
      WidgetsBinding.instance.addPostFrameCallback((_) => YouTubeLinkCache.prefetch(youtube, title));
    }
    final stats = state.stats;
    final gap = SizedBox(height: compact ? 8 : 12);

    Widget bigKey({required Key key, required IconData icon, required Color iconColor, required String title, required String sub, VoidCallback? onTap}) =>
        SizedBox(height: compact ? 60 : 64, child: IrKey(
          key: key,
          minHeight: compact ? 60 : 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onPressed: onTap,
          child: Center(child: Row(children: [
            Icon(icon, size: 30, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
              ]),
            ),
          ])),
        ));

    return ListView(
      padding: EdgeInsets.fromLTRB(12, compact ? 6 : 12, 12, 12),
      children: [
        _PanelHeader(
          state: state,
          title: l10n.camStreamTitle,
          subtitle: compact || info.active ? null : broadcastDetail(l10n, info),
          actions: [
            IconButton(
              key: const Key('camera-scoreboard-settings'),
              tooltip: l10n.scoreboardSettings,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: running ? () => _scoreboardSettings(context, ref) : null,
              icon: const Icon(Icons.scoreboard_outlined),
            ),
          ],
        ),
        if (replay != null) ...[
          _CameraReplayBar(replay: replay, enabled: running),
          gap,
        ],
        if (info.active)
          _OnAirCard(info: info, viewers: server.viewers, enabled: running, compact: compact)
        else
          _GoLive(info: info, enabled: running, compact: compact),
        gap,
        BroadcastMicButton(
          keyPrefix: 'camera-broadcast',
          on: info.audio,
          enabled: true,
          large: true,
          height: compact ? 52 : 64,
          onChanged: (on) async {
            final ok = await controller.setAudio(on);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).broadcastMicNextStream)));
            }
          },
        ),
        if (!info.active) ...[gap, const BroadcastChecklist()],
        gap,
        if (!compact) ...[
          Row(children: [
            Expanded(
              child: _Tile(
                key: const Key('camera-tile-battery'),
                label: l10n.cameraStatBattery,
                value: stats?.batteryPercent == null ? '–' : '${stats!.batteryPercent} %',
                alert: stats != null && !stats.plugged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                key: const Key('camera-tile-temperature'),
                label: l10n.camTileTemperature,
                value: _temperature(stats?.batteryTempC, digits: 0),
                alert: (state.thermalStatus ?? 0) >= _thermalModerate,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _Tile(
                  key: const Key('camera-tile-memory'),
                  label: l10n.camTileMemory,
                  value: '${(stats?.bufferMs ?? 0) ~/ 1000} s'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(key: const Key('camera-tile-viewers'), label: l10n.camTileViewers, value: '${server.viewers}'),
            ),
          ]),
          gap,
        ],
        bigKey(
          key: const Key('camera-pairing-open'),
          icon: Icons.qr_code_2,
          iconColor: c.signal,
          title: l10n.cameraConnectViewer,
          sub: l10n.camConnectViewerSub(server.viewers),
          onTap: () => showPairingSheet(context),
        ),
        if (youtube != null) ...[
          const SizedBox(height: 8),
          bigKey(
            key: const Key('camera-broadcast-qr'),
            icon: Icons.share,
            iconColor: c.live,
            title: l10n.camShareLive,
            sub: l10n.camShareLiveSub,
            onTap: () => shareYouTubeLive(context, youtube),
          ),
        ],
        const SizedBox(height: 8),
        if (info.active) ...[
          _SettingsButton(info: info, enabled: running),
          const SizedBox(height: 8),
        ],
        _BlackScreenButton(state: state, expand: true),
        gap,
        ..._notices(context, ref, state),
        _Advanced(state: state),
      ],
    );
  }

  Future<void> _scoreboardSettings(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(scoreboardControllerProvider);
    final ScoreboardState s = ref.read(scoreboardStateProvider).value ?? controller.current;
    final settings = await showScoreboardSettingsDialog(context, s.settings, state: s);
    if (settings != null) controller.apply(SettingsCommand(settings));
  }
}

/// Off air: the red Go live key (it opens the settings while there is no key) and "Prepare the
/// stream".
class _GoLive extends ConsumerWidget {
  const _GoLive({required this.info, required this.enabled, required this.compact});

  final BroadcastInfo info;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final failed = info.state == BroadcastStreamState.failed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (failed && info.message != null) ...[
        _Warning(Icons.error_outline, '${broadcastStateLabel(l10n, info.state)} · ${info.message}', error: true),
      ],
      Tooltip(
        message: broadcastDetail(l10n, info),
        child: SizedBox(
          height: compact ? 56 : 64,
          child: FilledButton(
            key: const ValueKey('camera-broadcast-start'),
            style: FilledButton.styleFrom(
              backgroundColor: c.live,
              foregroundColor: c.onLive,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              textStyle: TextStyle(fontFamily: IrFonts.sans, fontSize: compact ? 18 : 20, fontWeight: FontWeight.w700),
            ),
            onPressed: !enabled
                ? null
                : info.configured
                    ? () => _BroadcastActions.start(context, ref)
                    : () => _BroadcastActions.configure(context, ref, info),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IrLiveDot(color: c.onLive, size: 12, blink: false),
              const SizedBox(width: 10),
              Text(l10n.broadcastStart),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      _SettingsButton(info: info, enabled: enabled),
    ]);
  }
}

/// "Prepare the stream": opens the settings page.
class _SettingsButton extends ConsumerWidget {
  const _SettingsButton({required this.info, required this.enabled});

  final BroadcastInfo info;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return SizedBox(height: 48, child: IrKey(
      key: const ValueKey('camera-broadcast-settings'),
      minHeight: 48,
      semanticLabel: l10n.broadcastSettings,
      onPressed: enabled ? () => _BroadcastActions.configure(context, ref, info) : null,
      child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.tune, size: 20, color: c.text),
        const SizedBox(width: 8),
        Flexible(
          child: Text(l10n.camPrepareStream,
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        ),
      ])),
    ));
  }
}

/// On air: "Live on YouTube" in red, the time on air, the bitrate and the viewers, and an explicit
/// Stop (it asks first). One slim row on a phone.
class _OnAirCard extends ConsumerWidget {
  const _OnAirCard({required this.info, required this.viewers, required this.enabled, required this.compact});

  final BroadcastInfo info;
  final int viewers;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final live = info.state == BroadcastStreamState.live;
    final color = live ? c.live : c.warn;
    final uptime = info.uptimeMs == null ? '–' : formatRecordingClock(info.uptimeMs!);
    final mbps = info.bitrateKbps == null
        ? '–'
        : NumberFormat('0.0', Localizations.localeOf(context).toString()).format(info.bitrateKbps! / 1000);
    final state = Text(
      live ? (compact ? broadcastStateLabel(l10n, info.state) : l10n.camOnAirYouTube) : broadcastStateLabel(l10n, info.state),
      key: const ValueKey('camera-broadcast-state'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: compact ? 15 : 18, fontWeight: FontWeight.w700, color: live ? (compact ? c.text : c.onLive) : c.warnText),
    );
    Future<void> stop() async {
      if (await confirmStopBroadcast(context) && context.mounted) {
        await _BroadcastActions.run(context, ref.read(broadcastControllerProvider).stop);
      }
    }

    final stopButton = Material(
      color: c.liveSoft,
      child: InkWell(
        key: const ValueKey('camera-broadcast-stop'),
        onTap: enabled ? stop : null,
        child: Container(
          height: compact ? 48 : 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(compact ? l10n.camStopShort : l10n.camStopStream,
              style: TextStyle(fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700, color: c.liveText)),
        ),
      ),
    );

    if (compact) {
      return Container(
        key: const Key('camera-on-air'),
        decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          const SizedBox(width: 10),
          IrLiveDot(color: color, size: 9),
          const SizedBox(width: 8),
          Expanded(
            child: Row(children: [
              Flexible(child: state),
              const SizedBox(width: 6),
              Flexible(
                child: Text('$uptime · $mbps',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: irMono(13, weight: FontWeight.w500, color: c.muted)),
              ),
            ]),
          ),
          Container(width: 1, height: 48, color: c.live.withValues(alpha: 0.3)),
          stopButton,
        ]),
      );
    }

    Widget number(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: irMono(22, color: c.text)),
            Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        );
    return Container(
      key: const Key('camera-on-air'),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: live ? c.live : c.surface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            IrLiveDot(color: live ? c.onLive : c.warn, size: 10),
            const SizedBox(width: 10),
            Expanded(child: state),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            number(uptime, l10n.camOnAirFor),
            number(mbps, l10n.camMbps),
            number('$viewers', l10n.camViewersLabel),
          ]),
        ),
        Container(height: 1, color: c.live.withValues(alpha: 0.3)),
        stopButton,
      ]),
    );
  }
}

/// A clip on air (SPEC §12.6), put there by a viewer: the same speed and Back to live every
/// viewer has, applied straight to the Camera.
class _CameraReplayBar extends ConsumerWidget {
  const _CameraReplayBar({required this.replay, required this.enabled});

  final ReplayInfo replay;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(replayControllerProvider);
    return ReplayBar(
      keyPrefix: 'camera-replay',
      replay: replay,
      enabled: enabled,
      onSpeed: (speed) => _BroadcastActions.run(context, () => controller.setSpeed(speed)),
      onStop: () => _BroadcastActions.run(context, controller.stop),
    );
  }
}

/// The scoreboard strip, always on the broadcasting screen: the same controls a viewer has,
/// applied straight to the Camera's scoreboard; every viewer sees the change in its next status.
class _CameraScoreboardControls extends ConsumerWidget {
  const _CameraScoreboardControls({required this.state, required this.compact});

  final CameraSessionState state;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(scoreboardControllerProvider);
    final ScoreboardState s = ref.watch(scoreboardStateProvider).value ?? controller.current;
    return ScoreboardPanel(
      key: const Key('camera-scoreboard'),
      state: s,
      enabled: state.phase == CameraPhase.running,
      compact: compact,
      onCommand: controller.apply,
    );
  }
}

/// The stream's actions on the Camera: Go live (preparing the YouTube live in account mode), the
/// settings page, and errors as snack bars.
abstract final class _BroadcastActions {
  static void start(BuildContext context, WidgetRef ref) =>
      _start(context, ref.read(broadcastControllerProvider), ref.read(youtubeAccountProvider));

  static void _start(BuildContext context, BroadcastController controller, YouTubeAccount? youtube) =>
      run(context, () async {
        // Account mode: a live must be there to receive the stream, and the Camera must use its key.
        if (youtube != null && youtube.active) {
          if (youtube.email == null) {
            _snack(context, AppLocalizations.of(context).youtubeNeedSignIn);
            return;
          }
          final target = await prepareYouTubeLive(context, youtube);
          if (target == null) return;
          await controller.configure(
            server: target.server,
            key: target.key,
            targetKbps: controller.targetKbps,
            audio: controller.audio,
          );
        }
        if (!context.mounted) return;
        if (!await controller.start() && context.mounted) {
          _snack(context, AppLocalizations.of(context).broadcastMicDenied);
        }
      });

  /// "Prepare the stream"; its red button saves and goes live.
  static Future<void> configure(BuildContext context, WidgetRef ref, BroadcastInfo info) async {
    final controller = ref.read(broadcastControllerProvider);
    final youtube = ref.read(youtubeAccountProvider);
    final result = await showBroadcastConfigDialog(
      context,
      info,
      youtube: youtube,
      canGoLive: !info.active,
      checklist: const BroadcastChecklist(inPage: true),
    );
    if (result == null) return;
    await controller.configure(
      server: result.server,
      key: result.key,
      targetKbps: result.targetKbps,
      audio: result.audio,
      replayScoreboard: result.replayScoreboard,
    );
    if (result.goLive && context.mounted) _start(context, controller, youtube);
  }

  static Future<void> run(BuildContext context, Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    try {
      await action();
    } on BroadcastException catch (e) {
      if (context.mounted) _snack(context, broadcastErrorMessage(l10n, e.code, e.message));
    } on PlatformException catch (e) {
      if (context.mounted) _snack(context, l10n.broadcastFailed(e.message ?? e.code));
    } catch (e) {
      if (context.mounted) _snack(context, l10n.broadcastFailed('$e'));
    }
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// The stream on the black operating screen: state and numbers, dim; Go live / Stop stay at hand.
class _OperatingBroadcastBar extends ConsumerWidget {
  const _OperatingBroadcastBar({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(broadcastControllerProvider);
    final info = ref.watch(broadcastInfoProvider).value ?? controller.info;
    return BroadcastBar(
      key: const Key('camera-broadcast'),
      info: info,
      enabled: enabled,
      keyPrefix: 'camera-broadcast',
      buttonSize: 56,
      dim: true,
      onStart: () => _BroadcastActions.start(context, ref),
      onStop: () => _BroadcastActions.run(context, controller.stop),
      onConfigure: () => _BroadcastActions.configure(context, ref, info),
    );
  }
}

/// `LOC 2 – 1 VIS 12:34 1T`: the score as it goes on air, large and dim on the operating screen.
class _CameraScoreLine extends ConsumerWidget {
  const _CameraScoreLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ScoreboardState s =
        ref.watch(scoreboardStateProvider).value ?? ref.watch(scoreboardControllerProvider).current;
    final dim = _OperatingViewState.dim;
    const size = 40.0;
    final style = irMono(size, color: dim);
    Widget name(String text, int color) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 5, height: size * 0.6, color: Color(color).withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Text(ScoreboardState.displayName(text, s.style),
              style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w700, color: dim)),
        ]);
    final label = periodLabel(l10n, period: s.period, periods: s.periods);
    return Wrap(
      key: const Key('camera-score'),
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        name(s.home.name, s.home.color),
        Text('${s.home.score} – ${s.away.score}', style: style),
        name(s.away.name, s.away.color),
        ScoreboardClock(state: s, builder: (_, ms) => Text(formatClock(ms), style: style)),
        if (label.isNotEmpty) Text(label, style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w700, color: dim)),
        if (!s.visible) Icon(Icons.visibility_off, size: size * 0.7, color: dim),
      ],
    );
  }
}

// endregion

// region Operating mode

/// Pure black with dim status tiles readable at a glance, so an AMOLED screen draws almost
/// nothing. Tap to wake.
class _OperatingView extends ConsumerStatefulWidget {
  const _OperatingView();

  @override
  ConsumerState<_OperatingView> createState() => _OperatingViewState();
}

class _OperatingViewState extends ConsumerState<_OperatingView> {
  /// Always the dark palette, dimmed: the screen is black whatever the theme.
  static final dim = IrColors.dark.muted.withValues(alpha: 0.5);
  static final dimRed = IrColors.dark.live.withValues(alpha: 0.5);

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
    final style = TextStyle(color: dim, fontSize: 14);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const Key('camera-operating'),
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(cameraSessionProvider.notifier).stopOperating(),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (state.broadcast) ...[
                  const _CameraScoreLine(),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _OperatingBroadcastBar(enabled: running),
                  ),
                  const SizedBox(height: 8),
                ],
                // The recording stays at hand without waking the screen; the buttons take their
                // own taps, everything around them wakes to setup.
                _CameraRecording(state: state, dim: true),
                const SizedBox(height: 12),
                for (final r in state.recovered) Text(l10n.recRecovered(formatRecordingSpan(r.durationMs)), style: style),
                for (final e in state.errors.take(2)) Text(e, style: style.copyWith(color: dimRed)),
                // A Wrap, not a Row: the tiles never overflow on a small landscape phone.
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _DimTile(
                    key: const Key('camera-op-capture'),
                    icon: Icons.fiber_manual_record,
                    iconColor: running ? dimRed : dim,
                    value: '${(stats?.bufferMs ?? 0) ~/ 1000} s',
                    label: l10n.camTileMemory,
                  ),
                  _DimTile(
                    key: const Key('camera-op-outbox'),
                    icon: Icons.outbox,
                    value: '${stats?.outboxClips ?? 0}',
                    label: l10n.camTileOutbox,
                  ),
                  _DimTile(
                    key: const Key('camera-op-temperature'),
                    icon: Icons.thermostat,
                    iconColor: hot ? dimRed : null,
                    value: _temperature(stats?.batteryTempC),
                    label: hot ? thermalName(l10n, state.thermalStatus!) : l10n.camTileTemperature,
                    alert: hot,
                  ),
                  _DimTile(
                    key: const Key('camera-op-battery'),
                    icon: stats != null && !stats.plugged ? Icons.power_off : Icons.battery_charging_full,
                    iconColor: stats != null && !stats.plugged ? dimRed : null,
                    value: stats?.batteryPercent == null ? '–' : '${stats!.batteryPercent} %',
                    label: stats != null && !stats.plugged ? l10n.cameraNotCharging : l10n.camTileCharging,
                    alert: stats != null && !stats.plugged,
                  ),
                  _DimTile(
                    key: const Key('camera-op-viewers'),
                    icon: Icons.people,
                    value: '$viewers',
                    label: l10n.cameraOperatingViewers(viewers),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(l10n.cameraOperatingHint, style: TextStyle(color: dim.withValues(alpha: 0.35), fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A status tile on the black screen: a glyph, a figure and a word, all dim.
class _DimTile extends StatelessWidget {
  const _DimTile({super.key, required this.icon, required this.value, required this.label, this.iconColor, this.alert = false});

  final IconData icon;
  final String value;
  final String label;
  final Color? iconColor;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final dim = _OperatingViewState.dim;
    final color = alert ? _OperatingViewState.dimRed : dim;
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border.all(color: alert ? _OperatingViewState.dimRed : dim.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: iconColor ?? dim),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: irMono(20, color: color, height: 1.1)),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ]),
      ]),
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

String _temperature(double? celsius, {int digits = 1}) => celsius == null ? '–' : '${celsius.toStringAsFixed(digits)} °C';

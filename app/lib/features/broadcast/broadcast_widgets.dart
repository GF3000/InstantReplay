import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../recording/recording_widgets.dart' show formatRecordingClock;

export 'ui/scoreboard_panel.dart';
export 'ui/scoreboard_settings_page.dart';
export 'ui/stream_setup_page.dart';
export 'ui/youtube_share.dart';

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

/// Red on air, amber while connecting, muted off air; half as bright on the black operating
/// screen ([dim]).
Color broadcastStateColor(BuildContext context, BroadcastStreamState state, {bool dim = false}) {
  final c = context.ir;
  final color = switch (state) {
    BroadcastStreamState.live || BroadcastStreamState.failed => c.live,
    BroadcastStreamState.connecting || BroadcastStreamState.reconnecting => c.warn,
    BroadcastStreamState.idle => c.muted,
  };
  return dim ? color.withValues(alpha: 0.5) : color;
}

/// Why a broadcast command was refused, from the Camera's error code.
String broadcastErrorMessage(AppLocalizations l10n, String code, String? message) => switch (code) {
      'not_configured' => l10n.broadcastNotConfigured,
      'mic_permission' => l10n.broadcastMicDenied,
      'not_broadcast_mode' => l10n.broadcastNotBroadcastMode,
      'not_live' => l10n.replayNotLive,
      'replay_unavailable' => l10n.replayUnavailable,
      'replay_failed' => l10n.replayFailed(message ?? code),
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
    this.onShare,
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

  /// Shows the live's link as a QR code; null without a YouTube account live.
  final VoidCallback? onShare;

  /// Prefix of the buttons' keys, e.g. `viewer-broadcast` → `viewer-broadcast-start`.
  final String keyPrefix;
  final double buttonSize;

  /// The Camera's black operating screen.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final color = broadcastStateColor(context, info.state, dim: dim);
    final detail = broadcastDetail(l10n, info);
    final size = buttonSize;
    final dimColor = c.muted.withValues(alpha: 0.55);
    final fg = dim ? dimColor : null;
    final side = dim ? BorderSide(color: dimColor) : null;
    final live = info.state == BroadcastStreamState.live;
    return Row(children: [
      if (live && !dim) IrLiveDot(color: color) else Icon(live ? Icons.sensors : Icons.sensors_off, size: 20, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            broadcastStateLabel(l10n, info.state),
            key: ValueKey('$keyPrefix-state'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: dim || live ? color : c.text, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: irMono(12, weight: FontWeight.w500, color: dim ? dimColor : c.muted),
            ),
        ]),
      ),
      if (!dim && onShare != null)
        IconButton(
          key: ValueKey('$keyPrefix-qr'),
          tooltip: l10n.youtubeQrTitle,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          onPressed: onShare,
          icon: const Icon(Icons.qr_code_2),
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
          style: OutlinedButton.styleFrom(
            minimumSize: Size(size, size),
            foregroundColor: fg ?? c.liveText,
            side: side ?? BorderSide(color: c.live),
          ),
          onPressed: enabled ? () => _stop(context) : null,
          icon: const Icon(Icons.stop),
          label: Text(l10n.broadcastStop),
        )
      else
        FilledButton.icon(
          key: ValueKey('$keyPrefix-start'),
          style: FilledButton.styleFrom(
            minimumSize: Size(size, size),
            backgroundColor: dim ? Colors.transparent : c.live,
            foregroundColor: dim ? dimColor : c.onLive,
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

/// The stream in a header: settings, then one button that says Go live (red) when idle and, on
/// air, shows the state with the bitrate and the time on air; tapping it then asks to stop.
class BroadcastHeaderControls extends StatelessWidget {
  const BroadcastHeaderControls({
    super.key,
    required this.info,
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onConfigure,
    this.onShare,
    this.keyPrefix = 'broadcast',
  });

  final BroadcastInfo info;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onConfigure;

  /// Shows the live's link as a QR code; null without a YouTube account live.
  final VoidCallback? onShare;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final Widget button;
    if (info.active) {
      final color = broadcastStateColor(context, info.state);
      final numbers = [
        if (info.bitrateKbps case final kbps?) l10n.broadcastBitrate((kbps / 1000).toStringAsFixed(1)),
        if (info.uptimeMs case final ms?) formatRecordingClock(ms),
      ].join(' · ');
      final label = info.state == BroadcastStreamState.live && numbers.isNotEmpty
          ? numbers
          : broadcastStateLabel(l10n, info.state);
      button = OutlinedButton.icon(
        key: ValueKey('$keyPrefix-stop'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: color,
          side: BorderSide(color: color, width: 2),
        ),
        onPressed: enabled ? () => _stop(context) : null,
        icon: Icon(info.state == BroadcastStreamState.live ? Icons.sensors : Icons.sync),
        label: Text(
          label,
          key: ValueKey('$keyPrefix-state'),
          style: irMono(14, color: color),
        ),
      );
    } else {
      button = FilledButton.icon(
        key: ValueKey('$keyPrefix-start'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: c.live,
          foregroundColor: c.onLive,
        ),
        onPressed: enabled && info.configured ? onStart : (enabled ? onConfigure : null),
        icon: const Icon(Icons.sensors),
        label: Text(l10n.broadcastStart, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (onShare != null)
        IconButton(
          key: ValueKey('$keyPrefix-qr'),
          tooltip: l10n.youtubeQrTitle,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: onShare,
          icon: const Icon(Icons.qr_code_2),
        ),
      IconButton(
        key: ValueKey('$keyPrefix-settings'),
        tooltip: l10n.broadcastSettings,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: enabled ? onConfigure : null,
        icon: const Icon(Icons.settings),
      ),
      Tooltip(message: broadcastDetail(l10n, info), child: button),
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

/// The stream's microphone, on or off with one tap (SPEC §12.7): on air at once while
/// streaming, and remembered for the next stream. Red means YouTube hears nothing.
///
/// Compact by default (an icon key for top bars); [large] makes it the full-width row of the
/// Camera's broadcasting screen ("Microphone on · tap to turn it off").
class BroadcastMicButton extends StatelessWidget {
  const BroadcastMicButton({
    super.key,
    required this.on,
    required this.enabled,
    required this.onChanged,
    this.keyPrefix = 'broadcast',
    this.large = false,
    this.height,
    this.levelDb,
  });

  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String keyPrefix;
  final bool large;

  /// Height of the large row; 64 by default.
  final double? height;

  /// What the microphone hears, in dBFS (null: no open mic, no meter). Listening to it is what
  /// makes the Camera poll the level, so it only runs while this button is on screen.
  final ValueListenable<double?>? levelDb;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget toggle(double? db) => IrMicToggle(
          key: ValueKey('$keyPrefix-mic'),
          open: on,
          level: IrMicToggle.levelFromDbfs(db),
          onTap: enabled ? () => onChanged(!on) : null,
          openLabel: large ? l10n.camMicOpen : null,
          closedLabel: large ? l10n.camMicClosed : null,
          subtitle: large ? (on ? l10n.camMicOpenHint : l10n.camMicClosedHint) : null,
          height: large ? (height ?? 64) : 48,
        );
    final level = levelDb;
    return Tooltip(
      message: on ? l10n.broadcastMicMute : l10n.broadcastMicUnmute,
      child: level == null
          ? toggle(null)
          : ValueListenableBuilder<double?>(valueListenable: level, builder: (_, db, _) => toggle(db)),
    );
  }
}

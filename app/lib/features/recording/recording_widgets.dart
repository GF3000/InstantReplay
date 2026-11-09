import 'package:flutter/material.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../l10n/app_localizations.dart';

// Full-session recording (SPEC §3.8) as both roles show it: the Camera for its own buttons, every
// Viewer from the status the Camera pushes. One recording lives on the Camera; anyone can drive it.

/// Seconds of buffer the "include the last" option keeps from before the press.
const recordIncludeSeconds = 30;

/// `12:34` or `1:02:03`.
String formatRecordingClock(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// A rough length for people: `2 h 10 min`, `47 min`, `30 s`.
String formatRecordingSpan(int ms) {
  if (ms < 60000) return '${(ms / 1000).round()} s';
  final minutes = ms ~/ 60000, h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The note for a recording that just ended, by why it ended.
String recordingSavedMessage(AppLocalizations l10n, {required int parts, required int durationMs, required RecordingEndReason reason}) {
  final duration = formatRecordingSpan(durationMs);
  return switch (reason) {
    RecordingEndReason.user => l10n.recSaved(parts, duration),
    RecordingEndReason.lowSpace => l10n.recSavedLowSpace(duration),
    RecordingEndReason.error => l10n.recSavedError(duration),
    RecordingEndReason.recovered => l10n.recRecovered(duration),
  };
}

/// Why a start, pause or finish was refused, from the Camera's error code.
String recordingErrorMessage(AppLocalizations l10n, String code, String? message) =>
    code == 'no_space' ? l10n.recNoSpace : l10n.recFailed(message ?? code);

/// Asks before finishing: a finished recording cannot be resumed. True to finish.
Future<bool> confirmFinishRecording(BuildContext context, int elapsedMs) async {
  final l10n = AppLocalizations.of(context);
  final finish = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.recFinishTitle),
      content: Text(l10n.recFinishBody(formatRecordingClock(elapsedMs))),
      actions: [
        TextButton(
          key: const ValueKey('rec-finish-keep'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.recFinishKeep),
        ),
        FilledButton(
          key: const ValueKey('rec-finish-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.recFinish),
        ),
      ],
    ),
  );
  return finish ?? false;
}

/// One compact row: the state and time on the left, the buttons on the right.
///
/// Idle: a labelled Record button. Recording: Pause and Finish. Paused: Resume and Finish. Record
/// and Resume carry a ▾ menu (also on long-press) with "including the last 30 s". Finish asks
/// first. [recording] null means idle with nothing known about space yet.
class RecordingBar extends StatefulWidget {
  const RecordingBar({
    super.key,
    required this.recording,
    required this.enabled,
    required this.onRecord,
    required this.onPause,
    required this.onFinish,
    this.keyPrefix = 'rec',
    this.buttonSize = 48,
    this.dim = false,
  });

  final SessionRecording? recording;

  /// False while the Camera is not capturing or not reachable.
  final bool enabled;
  final void Function(int includeSeconds) onRecord;
  final VoidCallback onPause;
  final VoidCallback onFinish;

  /// Prefix of the buttons' keys, e.g. `viewer-rec` → `viewer-rec-record`.
  final String keyPrefix;
  final double buttonSize;

  /// The Camera's black operating screen: dim colours so an AMOLED screen draws almost nothing.
  final bool dim;

  static const dimColor = Color(0xFF5A5A5A);
  static const dimRed = Color(0xFF8A2A2A);

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rec = widget.recording;
    final state = rec?.state ?? SessionRecordingState.idle;
    final enabled = widget.enabled;
    final size = widget.buttonSize;
    final red = widget.dim ? RecordingBar.dimRed : const Color(0xFFE53935);
    final fg = widget.dim ? RecordingBar.dimColor : null;
    final prefix = widget.keyPrefix;
    final constraints = BoxConstraints.tightFor(width: size, height: size);
    final dimSide = widget.dim ? const BorderSide(color: RecordingBar.dimColor) : null;

    Widget menu(Widget Function(MenuController) child) => MenuAnchor(
          controller: _menu,
          menuChildren: [
            MenuItemButton(
              key: const ValueKey('rec-include-0'),
              leadingIcon: Icon(Icons.fiber_manual_record, color: red),
              style: MenuItemButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: () => widget.onRecord(0),
              child: Text(state == SessionRecordingState.paused ? l10n.recResumeFromNow : l10n.recFromNow),
            ),
            MenuItemButton(
              key: ValueKey('rec-include-$recordIncludeSeconds'),
              leadingIcon: const Icon(Icons.history),
              style: MenuItemButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: () => widget.onRecord(recordIncludeSeconds),
              child: Text(state == SessionRecordingState.paused
                  ? l10n.recResumeIncludeLast(recordIncludeSeconds)
                  : l10n.recIncludeLast(recordIncludeSeconds)),
            ),
          ],
          builder: (context, controller, _) => child(controller),
        );

    void toggleMenu(MenuController c) => c.isOpen ? c.close() : c.open();

    final buttons = <Widget>[
      // Record and Resume are buttons with a long-press (an IconButton's tooltip would take it).
      if (state == SessionRecordingState.idle)
        SizedBox(
          height: size,
          child: FilledButton.tonalIcon(
            key: ValueKey('$prefix-record'),
            style: FilledButton.styleFrom(
              minimumSize: Size(size, size),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              foregroundColor: fg,
              backgroundColor: widget.dim ? Colors.transparent : null,
              side: dimSide,
            ),
            onPressed: enabled ? () => widget.onRecord(0) : null,
            onLongPress: enabled ? _menu.open : null,
            icon: Icon(Icons.fiber_manual_record, color: enabled ? red : null),
            label: Text(l10n.recRecord, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        )
      else if (state == SessionRecordingState.paused)
        FilledButton.tonal(
          key: ValueKey('$prefix-record'),
          style: FilledButton.styleFrom(
            fixedSize: Size(size, size),
            minimumSize: Size(size, size),
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
            backgroundColor: widget.dim ? Colors.transparent : null,
            side: dimSide,
          ),
          onPressed: enabled ? () => widget.onRecord(0) : null,
          onLongPress: enabled ? _menu.open : null,
          child: Icon(Icons.fiber_manual_record, color: enabled ? red : null, semanticLabel: l10n.recResume),
        )
      else
        IconButton.filledTonal(
          key: ValueKey('$prefix-pause'),
          tooltip: l10n.recPause,
          constraints: constraints,
          color: fg,
          style: widget.dim ? IconButton.styleFrom(backgroundColor: Colors.transparent, side: dimSide) : null,
          onPressed: enabled ? widget.onPause : null,
          icon: const Icon(Icons.pause),
        ),
      if (state != SessionRecordingState.recording)
        menu((controller) => SizedBox(
              width: size * 0.75,
              height: size,
              child: IconButton(
                key: ValueKey('$prefix-record-menu'),
                tooltip: l10n.recOptions,
                padding: EdgeInsets.zero,
                color: fg,
                onPressed: enabled ? () => toggleMenu(controller) : null,
                icon: const Icon(Icons.arrow_drop_down),
              ),
            )),
      if (state != SessionRecordingState.idle) ...[
        const SizedBox(width: 4),
        IconButton.outlined(
          key: ValueKey('$prefix-finish'),
          tooltip: l10n.recFinish,
          constraints: constraints,
          color: fg,
          style: widget.dim ? IconButton.styleFrom(side: dimSide) : null,
          onPressed: enabled ? () => _finish(context) : null,
          icon: const Icon(Icons.stop),
        ),
      ],
    ];

    return Row(children: [
      Expanded(child: RecordingStatusText(recording: rec, dim: widget.dim, alertColor: widget.dim ? red : scheme.error)),
      const SizedBox(width: 8),
      ...buttons,
    ]);
  }

  Future<void> _finish(BuildContext context) async {
    final elapsed = widget.recording?.elapsedMs ?? 0;
    if (await confirmFinishRecording(context, elapsed) && mounted) widget.onFinish();
  }
}

/// Two short lines: the state and recorded time, then the time left or a low-space warning.
class RecordingStatusText extends StatelessWidget {
  const RecordingStatusText({super.key, required this.recording, this.dim = false, this.alertColor});

  final SessionRecording? recording;
  final bool dim;
  final Color? alertColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rec = recording;
    final state = rec?.state ?? SessionRecordingState.idle;
    final alert = alertColor ?? theme.colorScheme.error;
    final base = dim ? RecordingBar.dimColor : theme.colorScheme.onSurface;
    final muted = dim ? RecordingBar.dimColor : theme.colorScheme.onSurfaceVariant;

    final part = rec != null && rec.parts > 1 ? ' · ${l10n.recPart(rec.parts)}' : '';
    final (IconData icon, Color iconColor, String title) = switch (state) {
      SessionRecordingState.recording => (
          Icons.fiber_manual_record,
          dim ? RecordingBar.dimRed : const Color(0xFFE53935),
          '${formatRecordingClock(rec!.elapsedMs)}$part'
        ),
      SessionRecordingState.paused => (Icons.pause_circle, muted, '${l10n.recPaused(formatRecordingClock(rec!.elapsedMs))}$part'),
      SessionRecordingState.idle => (Icons.videocam_outlined, muted, l10n.recTitle),
    };

    final remaining = rec?.remainingMs;
    final String? detail;
    var warn = false;
    if (rec != null && rec.lowSpace) {
      warn = true;
      detail = remaining == null ? l10n.recLowSpaceUnknown : l10n.recLowSpace(formatRecordingSpan(remaining));
    } else if (remaining != null) {
      detail = l10n.recRemaining(formatRecordingSpan(remaining));
    } else if (rec != null) {
      detail = l10n.recFree((rec.freeBytes / 1e9).toStringAsFixed(1));
    } else {
      detail = l10n.recIdle;
    }

    return Row(children: [
      Icon(icon, size: 18, color: iconColor),
      const SizedBox(width: 6),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            title,
            key: const ValueKey('rec-status-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: base,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Row(children: [
            if (warn) ...[Icon(Icons.warning_rounded, size: 14, color: alert), const SizedBox(width: 2)],
            Flexible(
              child: Text(
                detail,
                key: const ValueKey('rec-status-detail'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: warn ? alert : muted, fontWeight: warn ? FontWeight.bold : null),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

/// The full-session recording as one small control (SPEC §3.8): a camera icon while idle, a
/// `● 12:34` pill while recording (`⏸ 12:34` paused). Tapping it opens [showRecordingDialog]
/// with the state, the time recorded, the space left and the actions, so a stray tap never
/// starts or stops anything.
class RecordingButton extends StatelessWidget {
  const RecordingButton({
    super.key,
    required this.recording,
    required this.enabled,
    required this.onRecord,
    required this.onPause,
    required this.onFinish,
    this.keyPrefix = 'rec',
    this.dim = false,
    this.overVideo = false,
  });

  final SessionRecording? recording;
  final bool enabled;
  final void Function(int includeSeconds) onRecord;
  final VoidCallback onPause;
  final VoidCallback onFinish;

  /// Prefix of the keys: `<prefix>-button`, and in the dialog `<prefix>-record`,
  /// `<prefix>-record-include`, `<prefix>-pause`, `<prefix>-finish`.
  final String keyPrefix;

  /// The Camera's black operating screen.
  final bool dim;

  /// Drawn over the camera preview: a dark backing keeps it readable.
  final bool overVideo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rec = recording;
    final state = rec?.state ?? SessionRecordingState.idle;
    final red = dim ? RecordingBar.dimRed : const Color(0xFFE53935);
    final fg = dim ? RecordingBar.dimColor : (overVideo ? Colors.white : null);
    void open() => showRecordingDialog(
          context,
          recording: rec,
          onRecord: onRecord,
          onPause: onPause,
          onFinish: onFinish,
          keyPrefix: keyPrefix,
        );
    if (state == SessionRecordingState.idle) {
      return IconButton(
        key: ValueKey('$keyPrefix-button'),
        tooltip: l10n.recTitle,
        color: fg,
        style: overVideo ? IconButton.styleFrom(backgroundColor: Colors.black54) : null,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: enabled ? open : null,
        icon: const Icon(Icons.videocam_outlined),
      );
    }
    final recordingNow = state == SessionRecordingState.recording;
    final warn = rec?.lowSpace ?? false;
    return Tooltip(
      message: l10n.recTitle,
      child: OutlinedButton.icon(
        key: ValueKey('$keyPrefix-button'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: dim ? RecordingBar.dimColor : (recordingNow ? red : fg),
          backgroundColor: overVideo ? Colors.black54 : null,
          side: BorderSide(color: recordingNow || warn ? red : (fg ?? Colors.grey), width: recordingNow ? 2 : 1),
        ),
        onPressed: enabled ? open : null,
        icon: Icon(recordingNow ? Icons.fiber_manual_record : Icons.pause, size: 16, color: recordingNow ? red : fg),
        label: Text(
          formatRecordingClock(rec!.elapsedMs),
          key: const ValueKey('rec-button-time'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// The recording's state (time, parts, space left) and what can be done from it: start, or
/// include the last 30 s; pause; resume; finish (which asks again, it cannot be undone).
Future<void> showRecordingDialog(
  BuildContext context, {
  required SessionRecording? recording,
  required void Function(int includeSeconds) onRecord,
  required VoidCallback onPause,
  required VoidCallback onFinish,
  String keyPrefix = 'rec',
}) {
  final l10n = AppLocalizations.of(context);
  final state = recording?.state ?? SessionRecordingState.idle;
  const red = Color(0xFFE53935);
  Widget action(String key, IconData icon, String label, VoidCallback onTap, {Color? color}) => SimpleDialogOption(
        key: ValueKey('$keyPrefix-$key'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        onPressed: onTap,
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
        ]),
      );
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      void run(VoidCallback f) {
        Navigator.of(dialogContext).pop();
        f();
      }

      return SimpleDialog(
        key: ValueKey('$keyPrefix-dialog'),
        title: Text(l10n.recTitle),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: RecordingStatusText(recording: recording),
          ),
          const Divider(),
          if (state != SessionRecordingState.recording) ...[
            action(
              'record',
              Icons.fiber_manual_record,
              state == SessionRecordingState.paused ? l10n.recResumeFromNow : l10n.recFromNow,
              () => run(() => onRecord(0)),
              color: red,
            ),
            action(
              'record-include',
              Icons.history,
              state == SessionRecordingState.paused
                  ? l10n.recResumeIncludeLast(recordIncludeSeconds)
                  : l10n.recIncludeLast(recordIncludeSeconds),
              () => run(() => onRecord(recordIncludeSeconds)),
            ),
          ],
          if (state == SessionRecordingState.recording)
            action('pause', Icons.pause, l10n.recPause, () => run(onPause)),
          if (state != SessionRecordingState.idle)
            action('finish', Icons.stop, l10n.recFinish, () async {
              Navigator.of(dialogContext).pop();
              if (await confirmFinishRecording(context, recording?.elapsedMs ?? 0)) onFinish();
            }),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart' show BroadcastInfo, BroadcastStreamState;

import '../../../core/panels.dart';
import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../broadcast/broadcast_widgets.dart';
import '../../camera/zoom_widgets.dart';
import '../../recording/recording_widgets.dart';
import '../../library/library_providers.dart' show liveClipsProvider;
import '../clips/clip_transfers.dart';
import '../data/session_link.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import '../viewer_providers.dart';
import 'clip_list.dart';
import 'replay_air.dart';
import '../../broadcast/youtube/youtube_providers.dart';

/// Main Viewer screen, "balanced" layout (UX §3.2): a large live view and a large Save key.
///
/// Portrait: live on top, Save + quick choices below, the cue list (filters + clips) underneath.
/// Landscape (phone, tablet, laptop): live on the left, a right panel with Save, the quick
/// choices, the filters and the cue list. After a save the tag panel shows over the live view:
/// dropping from its top in portrait, at its bottom-left corner in landscape.
///
/// In broadcast mode (SPEC §12) the scoreboard controls go right under the live view and the
/// stream row above Save; saving clips works as usual.
class LiveControlView extends ConsumerWidget {
  const LiveControlView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Recording news from the Camera: saved (by anyone, or because space ran out) or refused.
    ref.listen(viewerRecordingProvider, (_, notice) {
      final l10n = AppLocalizations.of(context);
      final text = switch (notice) {
        RecordingEnded(:final finished) => recordingSavedMessage(
          l10n,
          parts: finished.parts,
          durationMs: finished.durationMs,
          reason: finished.reason,
        ),
        RecordingRefused(:final code, :final message) => recordingErrorMessage(l10n, code, message),
        null => null,
      };
      if (text != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    ref.listen(viewerBroadcastNoticeProvider, (_, notice) {
      if (notice == null) return;
      final text = broadcastErrorMessage(AppLocalizations.of(context), notice.code, notice.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    final broadcast = ref.watch(viewerScoreboardProvider.select((s) => s != null));
    final onAir = ref.watch(viewerReplayProvider.select((r) => r != null));
    final hidden = ref.watch(hiddenPanelsProvider);
    return _layout(
      live: !hidden.contains(Panel.viewerLive),
      scoreboard: broadcast && !hidden.contains(Panel.viewerScoreboard),
      replays: !hidden.contains(Panel.viewerReplays),
      onAir: onAir,
    );
  }

  /// Each part can be hidden from the menu (SPEC §12.5): e.g. only the scoreboard for a
  /// scorekeeper, or only live + replays for the coach while the Camera keeps the score.
  ///
  /// While a clip is on air ([onAir]) the replay bar takes room: on a short portrait screen the
  /// live view (which shows the replay then) gives it up.
  Widget _layout({required bool live, required bool scoreboard, required bool replays, required bool onAir}) =>
      LayoutBuilder(
        builder: (context, c) {
          final ir = context.ir;
          // The full-session recording is in the menu (and its clock in the status pill).
          const bars = [ViewerBroadcastBar()];
          // A clip on air (SPEC §12.6): on top of the right panel, or above the scoreboard.
          const replayBar = ViewerReplayBar();
          Widget save({required bool compact, bool tight = false}) => SaveControls(compact: compact, tight: tight);
          const clips = Expanded(child: ClipList());
          if (!live && !scoreboard && !replays) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                replayBar,
                ...bars,
                const Expanded(child: _NothingShown()),
              ],
            );
          }
          final wide = c.maxWidth > c.maxHeight && c.maxWidth >= 560;
          if (wide) {
            final left = live || scoreboard;
            // Without the live view the scoreboard gets the room: full size, centred.
            final leftColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!replays) ...[replayBar, ...bars],
                if (live) const Expanded(child: _LiveWithTagPanel(dropDown: false)),
                // Tablet without the scoreboard: the session's clips on a time axis.
                if (live && replays && !scoreboard && c.maxHeight >= 600) ...[
                  const Divider(height: 1),
                  const MatchGlance(),
                ],
                if (scoreboard && live) ViewerScoreboardPanel(compact: c.maxHeight < 700),
                if (scoreboard && !live) const Expanded(child: Center(child: ViewerScoreboardPanel())),
              ],
            );
            final rightColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                replayBar,
                ...bars,
                save(compact: scoreboard || c.maxHeight < 480, tight: c.maxHeight < 400),
                const Divider(height: 1),
                const SizedBox(height: 4),
                clips,
              ],
            );
            if (!left) return rightColumn;
            if (!replays) return leftColumn;
            final panel = c.maxWidth >= 1000 ? 400.0 : (c.maxWidth * 0.42).clamp(260.0, 360.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: leftColumn),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: BorderDirectional(start: BorderSide(color: ir.line)),
                  ),
                  child: SizedBox(width: panel, child: rightColumn),
                ),
              ],
            );
          }
          final liveShare = scoreboard ? 0.3 : (replays ? 0.42 : 0.6);
          const minLive = 120.0;
          final liveMax = onAir && c.maxHeight < 760 ? minLive : c.maxHeight * liveShare;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (live)
                SizedBox(
                  height: (c.maxWidth * 9 / 16).clamp(minLive, liveMax < minLive ? minLive : liveMax),
                  child: const _LiveWithTagPanel(dropDown: true),
                ),
              replayBar,
              if (scoreboard) ViewerScoreboardPanel(compact: replays && c.maxHeight < 900),
              ...bars,
              if (replays) ...[
                save(compact: scoreboard || c.maxHeight < 760, tight: scoreboard && c.maxHeight < 760),
                clips,
              ] else
                const Spacer(),
            ],
          );
        },
      );
}

/// "Match at a glance" (tablet, under the live view): every clip of the session as a mark in its
/// tag's colour on a time axis, oldest on the left. Tap a mark to review that clip.
class MatchGlance extends ConsumerWidget {
  const MatchGlance({super.key});

  /// Tap area of a mark (the mark itself is 14 × 30).
  static const _markWidth = 32.0;
  static const _markHeight = 42.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final clips = ref.watch(liveClipsProvider);
    final clipTags = ref.watch(clipTagsProvider);
    final tags = ref.watch(tagsProvider);
    final inUse = tagsInUse(clips, clipTags, tags);
    final times = [for (final x in clips) x.requestedAt.millisecondsSinceEpoch];
    final first = times.isEmpty ? 0 : times.reduce((a, b) => a < b ? a : b);
    final last = times.isEmpty ? 0 : times.reduce((a, b) => a > b ? a : b);
    // At least ten minutes wide, so a few early clips do not spread over the whole axis.
    final span = (last - first).clamp(10 * 60000, 1 << 50);
    // Oldest first, so the newest marks are drawn on top.
    final ordered = [...clips]..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
    return Padding(
      key: const ValueKey('viewer-glance'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.liveGlanceTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            height: 92,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.line),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final usable = box.maxWidth - 2 * _markWidth;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(left: 0, right: 0, top: 45, height: 1, child: ColoredBox(color: c.line)),
                    for (final (i, clip) in ordered.indexed)
                      Positioned(
                        left: _markWidth / 2 + usable * (clip.requestedAt.millisecondsSinceEpoch - first) / span,
                        top: i.isEven ? 3 : 47,
                        width: _markWidth,
                        height: _markHeight,
                        child: _GlanceMark(clip: clip),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final t in inUse)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, color: t.colour),
                          const SizedBox(width: 6),
                          Text(t.label(l10n), style: TextStyle(fontSize: 13, color: c.muted)),
                        ],
                      ),
                  ],
                ),
              ),
              Text(l10n.liveGlanceHint, style: TextStyle(fontSize: 13, color: c.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlanceMark extends ConsumerWidget {
  const _GlanceMark({required this.clip});

  final SessionClip clip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final tag = ref.watch(clipTagProvider(clip.requestId));
    final colour = tag?.colour ?? c.muted;
    return Semantics(
      button: true,
      label: clipName(l10n, tag, clip.requestedAt),
      child: GestureDetector(
        key: ValueKey('glance-${clip.requestId}'),
        behavior: HitTestBehavior.opaque,
        onTap: clipOpener(context, ref, clip),
        child: Center(
          child: Container(
            width: 14,
            height: 30,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: colour.withValues(alpha: 0.6), blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every panel hidden: say how to bring them back.
class _NothingShown extends StatelessWidget {
  const _NothingShown();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        AppLocalizations.of(context).panelsNothingShown,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

/// The stream's microphone in the top bar (SPEC §12.7): one tap, red while closed. Nothing
/// outside broadcast mode. [labelled] adds "Mic on"/"Mic off" next to the icon (wide bars).
class ViewerMicButton extends ConsumerWidget {
  const ViewerMicButton({super.key, this.labelled = false});

  final bool labelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(viewerBroadcastProvider);
    if (info == null) return const SizedBox.shrink();
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    return Tooltip(
      message: info.audio ? l10n.broadcastMicMute : l10n.broadcastMicUnmute,
      child: Opacity(
        opacity: connected ? 1 : 0.45,
        child: IrMicToggle(
          key: const ValueKey('viewer-broadcast-mic'),
          open: info.audio,
          level: IrMicToggle.levelFromDbfs(ref.watch(viewerMicLevelProvider)),
          openLabel: labelled ? l10n.liveMicOpen : null,
          closedLabel: labelled ? l10n.liveMicClosed : null,
          // The stored key stays (key: null); the Camera applies it on air at once.
          onTap: connected
              ? () => remote.configure(server: info.server, targetKbps: info.targetKbps, audio: !info.audio)
              : null,
        ),
      ),
    );
  }
}

/// Switches that show or hide the Viewer's panels on this device (in the menu sheet).
class ViewerPanelToggles extends ConsumerWidget {
  const ViewerPanelToggles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hidden = ref.watch(hiddenPanelsProvider);
    final broadcast = ref.watch(viewerScoreboardProvider.select((s) => s != null));
    final panels = [
      (Panel.viewerLive, Icons.videocam_outlined, l10n.panelLive),
      if (broadcast) (Panel.viewerScoreboard, Icons.scoreboard_outlined, l10n.panelScoreboard),
      (Panel.viewerReplays, Icons.replay, l10n.panelReplays),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (panel, icon, label) in panels)
          SwitchListTile(
            key: ValueKey('viewer-panel-${panel.name}'),
            secondary: Icon(icon),
            title: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            value: !hidden.contains(panel),
            onChanged: (_) => ref.read(hiddenPanelsProvider.notifier).toggle(panel),
          ),
      ],
    );
  }
}

/// The live view, with the post-save tag panel over it: dropping from the top ([dropDown], phone
/// portrait) or at its bottom-left corner, so Save and the quick choices stay free for the next
/// play.
class _LiveWithTagPanel extends StatelessWidget {
  const _LiveWithTagPanel({required this.dropDown});

  final bool dropDown;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Stack(
      fit: StackFit.expand,
      children: [
        const LivePanel(),
        if (dropDown)
          const PositionedDirectional(
            start: 8,
            end: 8,
            top: 8,
            bottom: 8,
            child: Align(alignment: Alignment.topCenter, child: PostSaveTagPanel(dropDown: true)),
          )
        else
          PositionedDirectional(
            start: 12,
            top: 12,
            bottom: 12,
            width: (c.maxWidth - 24).clamp(0.0, 440.0),
            child: const Align(alignment: AlignmentDirectional.bottomStart, child: PostSaveTagPanel()),
          ),
      ],
    ),
  );
}

class LivePanel extends ConsumerWidget {
  const LivePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ir = context.ir;
    final live = ref.watch(liveViewProvider);
    final link = ref.watch(linkStateProvider.select((s) => s?.phase));
    final overlay = switch ((link, live.phase)) {
      (LinkPhase.connecting || null, _) => l10n.viewerLinkConnecting,
      (LinkPhase.reconnecting, _) => l10n.viewerLinkReconnecting,
      (_, LivePhase.waiting || LivePhase.negotiating) => l10n.viewerLiveStarting,
      (_, LivePhase.interrupted) => l10n.viewerLiveInterrupted,
      _ => null,
    };
    final zoom = ref.watch(viewerZoomProvider);
    final connected = link == LinkPhase.connected;
    final remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    final stream = ref.watch(viewerBroadcastProvider);
    final streaming = stream != null && stream.state == BroadcastStreamState.live;
    // The mic closed in broadcast mode: shown before going live too, so nobody starts silent by
    // mistake. The Camera itself shows no badge (its operator is not the one watching).
    final muted = stream != null && !stream.audio;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (live.peer case final peer?)
            zoom == null
                ? peer.buildView()
                : ZoomPinch(
                    ratio: zoom.ratio,
                    max: zoom.max,
                    enabled: connected,
                    onChanged: remote.zoom,
                    child: peer.buildView(),
                  ),
          if (overlay == null && connected)
            PositionedDirectional(
              start: 8,
              top: 8,
              child: _Badge(
                key: const ValueKey('viewer-live-badge'),
                text: l10n.liveOnAirBadge,
                // Red only when YouTube sees it.
                background: streaming ? ir.live : Colors.black.withValues(alpha: 0.72),
                foreground: streaming ? ir.onLive : Colors.white,
                dot: streaming ? null : ir.ok,
              ),
            ),
          if (muted)
            PositionedDirectional(
              end: 8,
              top: 8,
              child: _Badge(
                key: const ValueKey('viewer-no-sound-badge'),
                text: stream.active ? l10n.liveNoSoundBadge : l10n.liveMicClosedBadge,
                background: ir.live,
                foreground: ir.onLive,
                icon: Icons.mic_off,
              ),
            ),
          if (overlay != null) Center(child: _Connecting(text: overlay)),
          if (zoom != null && connected)
            Positioned(
              left: 4,
              bottom: 4,
              child: ZoomControl(
                keyPrefix: 'viewer-zoom',
                ratio: zoom.ratio,
                max: zoom.max,
                enabled: connected,
                onChanged: remote.zoom,
              ),
            ),
          if (link == LinkPhase.connected && live.phase != LivePhase.negotiating)
            PositionedDirectional(
              end: 6,
              bottom: 6,
              child: _RestartButton(onPressed: () => ref.read(liveViewProvider.notifier).restart()),
            ),
          const _SaveFlash(),
        ],
      ),
    );
  }
}

/// A small mono badge over the video ("LIVE", "STREAM WITHOUT SOUND").
class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.dot,
    this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final Color? dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(2)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
        ],
        if (icon != null) ...[Icon(icon, size: 13, color: foreground), const SizedBox(width: 4)],
        Text(
          text,
          style: irMono(11, weight: FontWeight.w600, color: foreground),
        ),
      ],
    ),
  );
}

/// Connecting / reconnecting / starting: a panel with a small spinner and the state, not a bare
/// spinner on black.
class _Connecting extends StatelessWidget {
  const _Connecting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        key: const ValueKey('viewer-live-overlay'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.lineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.signal)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restart the live view: a clear bordered button over the video.
class _RestartButton extends StatelessWidget {
  const _RestartButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.viewerLiveRestart,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          key: const ValueKey('viewer-live-restart'),
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    l10n.liveRestart,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short amber border flash over the live view after each save. Without motion (reduced
/// animations) the border just shows for the highlight time.
class _SaveFlash extends ConsumerStatefulWidget {
  const _SaveFlash();

  @override
  ConsumerState<_SaveFlash> createState() => _SaveFlashState();
}

class _SaveFlashState extends ConsumerState<_SaveFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = IrMotion.of(context);
    ref.listen(recentSaveProvider, (previous, next) {
      if (next != null && next != previous && motion) _c.forward(from: 0);
    });
    final recent = ref.watch(recentSaveProvider.select((r) => r != null));
    final amber = context.ir.signal;
    Widget border(double opacity) => IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          key: const ValueKey('viewer-save-flash'),
          decoration: BoxDecoration(border: Border.all(color: amber, width: 5)),
        ),
      ),
    );
    if (!motion) return recent ? border(0.8) : const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => _c.value >= 1 ? const SizedBox.shrink() : border(0.8 * (1 - _c.value)),
    );
  }
}

/// The Camera's full-session recording as one small control (SPEC §3.8): an icon, or the time
/// recorded; the actions are in its dialog. Hidden when the Camera does not offer it. The live
/// screen reaches it from the menu; this button is kept for other layouts.
class ViewerRecordingButton extends ConsumerWidget {
  const ViewerRecordingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(sessionRecordingProvider);
    if (recording == null) return const SizedBox.shrink();
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final capturing = ref.watch(linkStateProvider.select((s) => s?.status?.recording ?? false));
    final remote = ref.read(viewerRecordingProvider.notifier);
    return RecordingButton(
      key: const ValueKey('viewer-recording'),
      recording: recording,
      enabled: connected && capturing,
      keyPrefix: 'viewer-rec',
      onRecord: (seconds) => remote.record(includeSeconds: seconds),
      onPause: remote.pause,
      onFinish: remote.finish,
    );
  }
}

/// Opens the full-session recording dialog (start, pause, finish) from the menu.
void openViewerRecording(BuildContext context, WidgetRef ref) {
  final recording = ref.read(sessionRecordingProvider);
  final remote = ref.read(viewerRecordingProvider.notifier);
  showRecordingDialog(
    context,
    recording: recording,
    onRecord: (seconds) => remote.record(includeSeconds: seconds),
    onPause: remote.pause,
    onFinish: remote.finish,
    keyPrefix: 'viewer-rec',
  );
}

/// The scoreboard controls (SPEC §12.2) in broadcast mode; nothing otherwise.
class ViewerScoreboardPanel extends ConsumerWidget {
  const ViewerScoreboardPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreboard = ref.watch(viewerScoreboardProvider);
    if (scoreboard == null) return const SizedBox.shrink();
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    return Material(
      key: const ValueKey('viewer-scoreboard'),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: ScoreboardPanel(
          state: scoreboard,
          enabled: connected,
          compact: compact,
          onCommand: remote.command,
          controlsPanel: Panel.viewerScoreboard,
        ),
      ),
    );
  }
}

/// The YouTube stream's state with Go live / Stop and its settings (SPEC §12); nothing outside
/// broadcast mode.
class ViewerBroadcastBar extends ConsumerWidget {
  const ViewerBroadcastBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(viewerBroadcastProvider);
    if (info == null) return const SizedBox.shrink();
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    final youtube = ref.watch(youtubeActiveAccountProvider).value;
    if (youtube != null) {
      // Ask YouTube for the live's link now, so "Share the live" opens at once (no-op when known).
      final title = youtubeDefaultTitle(AppLocalizations.of(context), DateTime.now());
      WidgetsBinding.instance.addPostFrameCallback((_) => YouTubeLinkCache.prefetch(youtube, title));
    }
    return Padding(
      key: const ValueKey('viewer-broadcast'),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
      child: BroadcastBar(
        info: info,
        enabled: connected,
        keyPrefix: 'viewer-broadcast',
        onStart: () => _goLive(context, ref, info),
        onShare: youtube == null ? null : () => shareYouTubeLive(context, youtube),
        onStop: remote.stop,
        onConfigure: () async {
          final result = await showBroadcastConfigDialog(
            context,
            info,
            youtube: ref.read(youtubeAccountProvider),
            canGoLive: !info.active,
          );
          if (result == null) return;
          remote.configure(
            server: result.server,
            key: result.key,
            targetKbps: result.targetKbps,
            audio: result.audio,
            replayScoreboard: result.replayScoreboard,
          );
          if (result.goLive && context.mounted) await _goLive(context, ref, ref.read(viewerBroadcastProvider) ?? info);
        },
      ),
    );
  }

  /// Go live from the bar or from the stream setup page.
  static Future<void> _goLive(BuildContext context, WidgetRef ref, BroadcastInfo info) async {
    final remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    // Account mode: a live must be there to receive the stream, and the Camera must use its key.
    final account = ref.read(youtubeAccountProvider);
    if (account != null && account.active) {
      if (account.email == null) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).youtubeNeedSignIn)));
        return;
      }
      final target = await prepareYouTubeLive(context, account);
      if (target == null) return;
      remote.configure(server: target.server, key: target.key, targetKbps: info.targetKbps, audio: info.audio);
    }
    remote.start();
  }
}

/// The Save key (default preset) with an amber LED, "Save play", "the last N s and 2 s more" and
/// N in mono; under it the quick choices, which save at once with their own duration (D11). The
/// choice just used lights amber for a moment.
class SaveControls extends ConsumerWidget {
  const SaveControls({super.key, this.compact = false, this.tight = false});

  /// Short screens: a lower Save key so the clip list keeps some room.
  final bool compact;

  /// Very short screens (phone landscape): the lowest key, without its subtitle, so the clip
  /// list keeps about two rows.
  final bool tight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final presets = ref.watch(savePresetsProvider);
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final recording = ref.watch(linkStateProvider.select((s) => s?.status?.recording ?? true));
    final recent = ref.watch(recentSaveProvider);
    final enabled = connected && recording;
    void save(int? seconds) {
      final requestId = ref.read(viewerClipsProvider.notifier).save(seconds: seconds);
      if (requestId == null) return;
      ref.read(postSaveTagBarProvider.notifier).show(requestId);
      ref.read(recentSaveProvider.notifier).mark(requestId, seconds);
    }

    final keyHeight = tight ? 56.0 : (compact ? 72.0 : 92.0);
    final titleSize = tight ? 22.0 : (compact ? 24.0 : 28.0);
    final numberSize = tight ? 28.0 : (compact ? 34.0 : 40.0);
    final seconds = presets.defaultSeconds;

    final saveKey = IrKey(
      key: const ValueKey('viewer-save'),
      onPressed: enabled ? () => save(null) : null,
      led: c.signal,
      minHeight: keyHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      semanticLabel: l10n.viewerSave(seconds),
      // IrKey lays its child out from the top: fill the key below the LED.
      child: SizedBox(
        width: double.infinity,
        height: keyHeight - 8,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.liveSaveTitle,
                      maxLines: 1,
                      style: TextStyle(fontSize: titleSize, height: 1, fontWeight: FontWeight.w700, color: c.text),
                    ),
                  ),
                  if (!tight) ...[
                    const SizedBox(height: 5),
                    Text(
                      l10n.liveSaveSubtitle(seconds, presets.postSeconds),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$seconds'),
                  TextSpan(
                    text: 's',
                    style: TextStyle(fontSize: numberSize / 2),
                  ),
                ],
              ),
              style: irMono(numberSize, color: c.signal, height: 1),
            ),
          ],
        ),
      ),
    );

    final choices = Row(
      children: [
        for (final (i, s) in presets.quickSeconds.indexed)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 8),
              child: _QuickChoice(
                key: ValueKey('viewer-save-$s'),
                label: l10n.viewerSaveQuick(s),
                height: tight ? 48 : 50,
                selected: recent != null && recent.seconds == s,
                onTap: enabled ? () => save(s) : null,
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, tight ? 8 : 12, 12, tight ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          saveKey,
          SizedBox(height: tight ? 6 : 10),
          choices,
        ],
      ),
    );
  }
}

/// A quick save choice: a bordered mono button, amber while it is the save just made.
class _QuickChoice extends StatelessWidget {
  const _QuickChoice({
    super.key,
    required this.label,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double height;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final fg = selected ? c.signal : c.text;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: selected ? c.signalSoft : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: selected ? c.signal : c.line),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: height,
              child: Center(
                // Narrow panels (phone landscape, small windows): never split "10 s" over two lines.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: irMono(18, weight: FontWeight.w600, color: fg, height: 1.2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

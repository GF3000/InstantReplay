import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/panels.dart';
import '../../../l10n/app_localizations.dart';
import '../../broadcast/broadcast_widgets.dart';
import '../../camera/zoom_widgets.dart';
import '../../recording/recording_widgets.dart';
import '../data/session_link.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import '../viewer_providers.dart';
import 'clip_list.dart';
import 'replay_air.dart';

/// Main Viewer screen, "balanced" layout (UX §3.2): a large live view and a large Save button.
///
/// Portrait: live on top, Save + chips + tag bar below, clip list underneath. Landscape (phone,
/// tablet, laptop): live on the left, a right panel with Save, chips, tag bar and clip list. The
/// full-session recording row sits right above Save in both, one line high.
///
/// In broadcast mode (SPEC §12) the scoreboard controls go right under the live view and the
/// stream row above the recording row; saving clips works as usual.
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

  /// Each part can be hidden from the app bar (SPEC §12.5): e.g. only the scoreboard for a
  /// scorekeeper, or only live + replays for the coach while the Camera keeps the score.
  ///
  /// While a clip is on air ([onAir]) the replay bar takes room: on a short portrait screen the
  /// live view (which shows the replay then) gives it up.
  Widget _layout({required bool live, required bool scoreboard, required bool replays, required bool onAir}) =>
      LayoutBuilder(builder: (context, c) {
        const bars = [ViewerBroadcastBar(), ViewerRecordingBar()];
        // A clip on air (SPEC §12.6): on top of the right panel, or above the scoreboard.
        const replayBar = ViewerReplayBar();
        Widget save({required bool compact, bool tight = false}) => SaveControls(compact: compact, tight: tight);
        const clips = Expanded(child: ClipList());
        if (!live && !scoreboard && !replays) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            replayBar,
            ...bars,
            const Expanded(child: _NothingShown()),
          ]);
        }
        final wide = c.maxWidth > c.maxHeight && c.maxWidth >= 560;
        if (wide) {
          final left = live || scoreboard;
          // Without the live view the scoreboard gets the room: full size, centred.
          final leftColumn = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!replays) ...[replayBar, ...bars],
            if (live) const Expanded(child: _LiveWithTagPanel()),
            if (scoreboard && live) ViewerScoreboardPanel(compact: c.maxHeight < 700),
            if (scoreboard && !live) const Expanded(child: Center(child: ViewerScoreboardPanel())),
          ]);
          final rightColumn = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            replayBar,
            ...bars,
            save(compact: scoreboard || c.maxHeight < 480, tight: c.maxHeight < 400),
            const Divider(height: 1),
            clips,
          ]);
          if (!left) return rightColumn;
          if (!replays) return leftColumn;
          final panel = c.maxWidth >= 1000 ? 400.0 : (c.maxWidth * 0.42).clamp(260.0, 360.0);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: leftColumn),
            SizedBox(width: panel, child: rightColumn),
          ]);
        }
        final liveShare = scoreboard ? 0.3 : (replays ? 0.42 : 0.6);
        const minLive = 120.0;
        final liveMax = onAir && c.maxHeight < 760 ? minLive : c.maxHeight * liveShare;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (live)
            SizedBox(
              height: (c.maxWidth * 9 / 16).clamp(minLive, liveMax < minLive ? minLive : liveMax),
              child: const _LiveWithTagPanel(),
            ),
          replayBar,
          if (scoreboard) ViewerScoreboardPanel(compact: replays && c.maxHeight < 900),
          ...bars,
          if (replays) ...[
            save(compact: scoreboard || c.maxHeight < 760, tight: scoreboard && c.maxHeight < 760),
            const Divider(height: 1),
            clips,
          ] else
            const Spacer(),
        ]);
      });
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

/// The app bar menu that shows or hides the Viewer's panels on this device.
class ViewerPanelsButton extends ConsumerWidget {
  const ViewerPanelsButton({super.key});

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
    return PopupMenuButton<Panel>(
      key: const ValueKey('viewer-panels'),
      tooltip: l10n.panelsTitle,
      icon: const Icon(Icons.dashboard_customize_outlined),
      onSelected: ref.read(hiddenPanelsProvider.notifier).toggle,
      itemBuilder: (_) => [
        for (final (panel, icon, label) in panels)
          CheckedPopupMenuItem(
            key: ValueKey('viewer-panel-${panel.name}'),
            value: panel,
            checked: !hidden.contains(panel),
            child: Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]),
          ),
      ],
    );
  }
}

/// The live view, with the post-save tag panel sliding in over its left side: as wide as the
/// tags need (the whole view on a phone), so Save and the chips stay free for the next play.
class _LiveWithTagPanel extends StatelessWidget {
  const _LiveWithTagPanel();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Stack(fit: StackFit.expand, children: [
          const LivePanel(),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: c.maxWidth < 600 ? c.maxWidth : (c.maxWidth * 0.6).clamp(420.0, 640.0),
            child: const Align(alignment: AlignmentDirectional.topStart, child: PostSaveTagPanel()),
          ),
        ]),
      );
}

class LivePanel extends ConsumerWidget {
  const LivePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
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
        if (overlay != null)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(overlay, style: const TextStyle(color: Colors.white)),
            ]),
          ),
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
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton(
              color: Colors.white70,
              tooltip: l10n.viewerLiveRestart,
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(liveViewProvider.notifier).restart(),
            ),
          ),
      ]),
    );
  }
}

/// Record / Pause / Finish for the Camera's full-session recording, with the time recorded and
/// the space left (SPEC §3.8). Hidden when the Camera does not offer it (an older Camera).
class ViewerRecordingBar extends ConsumerWidget {
  const ViewerRecordingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(sessionRecordingProvider);
    if (recording == null) return const SizedBox.shrink();
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final capturing = ref.watch(linkStateProvider.select((s) => s?.status?.recording ?? false));
    final remote = ref.read(viewerRecordingProvider.notifier);
    return Padding(
      key: const ValueKey('viewer-recording'),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
      child: RecordingBar(
        recording: recording,
        enabled: connected && capturing,
        keyPrefix: 'viewer-rec',
        onRecord: (seconds) => remote.record(includeSeconds: seconds),
        onPause: remote.pause,
        onFinish: remote.finish,
      ),
    );
  }
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
        child: ScoreboardPanel(state: scoreboard, enabled: connected, compact: compact, onCommand: remote.command),
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
    return Padding(
      key: const ValueKey('viewer-broadcast'),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
      child: BroadcastBar(
        info: info,
        enabled: connected,
        keyPrefix: 'viewer-broadcast',
        onStart: remote.start,
        onStop: remote.stop,
        onConfigure: () async {
          final result = await showBroadcastConfigDialog(context, info);
          if (result == null) return;
          remote.configure(server: result.server, key: result.key, targetKbps: result.targetKbps, audio: result.audio);
        },
      ),
    );
  }
}

/// The big SAVE button (default preset), quick chips that save at once with their duration (D11),
/// and the post-save tag bar in a fixed slot below them.
class SaveControls extends ConsumerWidget {
  const SaveControls({super.key, this.compact = false, this.tight = false});

  /// Short screens: a lower Save button so the clip list keeps some room.
  final bool compact;

  /// Very short screens (phone landscape): the tag bar takes the chips' row while it shows, and
  /// the save hint is dropped, so the clip list keeps about two rows.
  final bool tight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final presets = ref.watch(savePresetsProvider);
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final recording = ref.watch(linkStateProvider.select((s) => s?.status?.recording ?? true));
    final enabled = connected && recording;
    void save(int? seconds) {
      final requestId = ref.read(viewerClipsProvider.notifier).save(seconds: seconds);
      if (requestId != null) ref.read(postSaveTagBarProvider.notifier).show(requestId);
    }

    final chips = Row(children: [
      for (final s in presets.quickSeconds)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OutlinedButton(
              key: ValueKey('viewer-save-$s'),
              onPressed: enabled ? () => save(s) : null,
              child: Text(l10n.viewerSaveQuick(s), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
    ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: tight ? 56 : (compact ? 64 : 88),
          child: FilledButton.icon(
            key: const ValueKey('viewer-save'),
            onPressed: enabled ? () => save(null) : null,
            icon: Icon(Icons.save_alt, size: compact ? 28 : 32),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                l10n.viewerSave(presets.defaultSeconds),
                style: TextStyle(fontSize: compact ? 22 : 26, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        chips,
        if (!tight) ...[
          const SizedBox(height: 4),
          Text(
            l10n.viewerSaveHint(presets.postSeconds),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ]),
    );
  }
}

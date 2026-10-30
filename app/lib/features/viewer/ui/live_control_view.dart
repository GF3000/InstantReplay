import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/session_link.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import '../viewer_providers.dart';
import 'clip_list.dart';

/// Main Viewer screen, "balanced" layout (UX §3.2): a large live view and a large Save button.
///
/// Portrait: live on top, Save + chips + tag bar below, clip list underneath. Landscape (phone,
/// tablet, laptop): live on the left, a right panel with Save, chips, tag bar and clip list.
class LiveControlView extends StatelessWidget {
  const LiveControlView({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight && c.maxWidth >= 560;
        if (wide) {
          final panel = c.maxWidth >= 1000 ? 400.0 : (c.maxWidth * 0.42).clamp(260.0, 360.0);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Expanded(child: LivePanel()),
            SizedBox(
              width: panel,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SaveControls(compact: c.maxHeight < 480, tight: c.maxHeight < 400),
                const Divider(height: 1),
                const Expanded(child: ClipList()),
              ]),
            ),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: (c.maxWidth * 9 / 16).clamp(120.0, c.maxHeight * 0.42), child: const LivePanel()),
          SaveControls(compact: c.maxHeight < 760),
          const Divider(height: 1),
          const Expanded(child: ClipList()),
        ]);
      });
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
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (live.peer case final peer?) peer.buildView(),
        if (overlay != null)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(overlay, style: const TextStyle(color: Colors.white)),
            ]),
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
        if (tight)
          PostSaveTagBar(idle: chips)
        else ...[
          chips,
          const SizedBox(height: 4),
          PostSaveTagBar(
            idle: Text(
              l10n.viewerSaveHint(presets.postSeconds),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ]),
    );
  }
}

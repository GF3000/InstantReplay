import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../broadcast/replay_widgets.dart';
import '../clips/clip_transfers.dart';
import '../data/session_link.dart';
import '../viewer_providers.dart';

// Replays on air from a Viewer (SPEC §12.6): the question when a clip could go on air, and the
// bar while one is.

/// A clip the Camera can put on air now: the stream is active ([streaming]) and the clip is
/// still on the Camera (ready, or in the reserve) and ready here.
bool canGoOnAir(SessionClip clip, {required bool streaming}) =>
    streaming && clip.onCamera && clip.clipId != null && clip.phase == SessionClipPhase.ready;

/// Opens [clip] for review. When it can go on air, first asks "Only on this tablet" or "Also on
/// air"; the latter also puts it on air. Dismissing the question opens nothing.
///
/// [route] gets whether the clip went on air: the review page then mirrors the stream (one speed
/// for both, and leaving it goes back to live).
Future<void> openClipReview(
  BuildContext context,
  WidgetRef ref,
  SessionClip clip,
  Route<void> Function({required bool onAir}) route,
) async {
  final streaming = ref.read(viewerBroadcastProvider)?.active ?? false;
  var air = false;
  if (canGoOnAir(clip, streaming: streaming)) {
    final choice = await askReplayOnAir(context);
    if (choice == null || !context.mounted) return;
    air = choice;
    if (air) ref.read(viewerBroadcastNoticeProvider.notifier).replayAir(clip.clipId!);
  }
  await Navigator.of(context).push(route(onAir: air));
}

/// "Only on this tablet" (false) or "Also on air" (true); null when dismissed.
Future<bool?> askReplayOnAir(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => SimpleDialog(
      key: const ValueKey('replay-choice'),
      title: Text(l10n.replayChoiceTitle),
      children: [
        _Choice(
          key: const ValueKey('replay-choice-tablet'),
          icon: Icons.tablet_android,
          label: l10n.replayChoiceTablet,
          onTap: () => Navigator.of(context).pop(false),
        ),
        _Choice(
          key: const ValueKey('replay-choice-air'),
          icon: Icons.sensors,
          label: l10n.replayChoiceAir,
          color: const Color(0xFFE53935),
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => SimpleDialogOption(
    onPressed: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 16),
        Flexible(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
      ],
    ),
  );
}

/// Speed and Back to live while a clip is on air, for every viewer; nothing otherwise. With
/// [clipId], only while that clip is on air (the review page).
class ViewerReplayBar extends ConsumerWidget {
  const ViewerReplayBar({super.key, this.clipId, this.speed = true, this.onStop});

  final String? clipId;

  /// False on the review page, whose own speed control drives the stream too.
  final bool speed;

  /// Instead of just sending replay_stop (the review page also closes itself).
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replay = ref.watch(viewerReplayProvider);
    if (replay == null || (clipId != null && replay.clipId != clipId)) return const SizedBox.shrink();
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: ReplayBar(
        keyPrefix: 'viewer-replay',
        replay: replay,
        enabled: connected,
        onSpeed: speed ? remote.replaySpeed : null,
        onStop: onStop ?? remote.replayStop,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../broadcast/replay_widgets.dart';
import '../clips/clip_transfers.dart';
import '../data/session_link.dart';
import '../viewer_providers.dart';

// Replays on air from a Viewer (SPEC §12.6): whether a clip can go on air, opening a review, and
// the bar while a clip is on air.

/// A clip the Camera can put on air now: the stream is active ([streaming]) and the clip is
/// still on the Camera (ready, or in the reserve) and ready here.
bool canGoOnAir(SessionClip clip, {required bool streaming}) =>
    streaming && clip.onCamera && clip.clipId != null && clip.phase == SessionClipPhase.ready;

/// Opens [clip] for review. Reviewing plays on this tablet only: when the clip can go on air,
/// the review page offers an explicit "Air replay" button ([canGoOnAir]).
///
/// [route] gets whether the clip is already on air (always false here; kept for callers that
/// open a review that mirrors the stream).
Future<void> openClipReview(
  BuildContext context,
  WidgetRef ref,
  SessionClip clip,
  Route<void> Function({required bool onAir}) route,
) =>
    Navigator.of(context).push(route(onAir: false));

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

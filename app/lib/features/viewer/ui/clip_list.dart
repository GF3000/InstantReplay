import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/library_providers.dart';
import '../clips/clip_transfers.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import '../viewer_providers.dart';
import 'replay_air.dart';
import 'review_page.dart';

/// "Bien · 12:41", or "Clip · 12:41" when untagged (UX §3.3).
String clipName(AppLocalizations l10n, ViewerTag? tag, DateTime requestedAt) {
  final time = DateFormat('HH:mm').format(requestedAt);
  return tag == null ? l10n.viewerClipUntagged(time) : l10n.viewerClipName(tag.label(l10n), time);
}

int clipSeconds(SessionClip clip) => clip.durationMs != null ? (clip.durationMs! / 1000).round() : clip.seconds.round();

/// The tag filter of the clip list; null shows every clip.
class ClipFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? tagId) => state = tagId;
}

final clipFilterProvider = NotifierProvider<ClipFilterNotifier, String?>(ClipFilterNotifier.new);

/// Tags used by at least one clip, in tag-set order: the filter chips.
List<ViewerTag> tagsInUse(List<SessionClip> clips, Map<String, String> clipTags, List<ViewerTag> tags) {
  final used = {for (final c in clips) ?clipTags[c.requestId]};
  return [
    for (final t in tags)
      if (used.contains(t.id)) t,
  ];
}

/// [clips] with tag [filter], or all of them when [filter] is null. Clips that are not ready yet
/// always show, so a save made while filtering never looks lost (it has no tag at first).
List<SessionClip> filterClips(List<SessionClip> clips, Map<String, String> clipTags, String? filter) => filter == null
    ? clips
    : [
        for (final c in clips)
          if (clipTags[c.requestId] == filter || c.phase != SessionClipPhase.ready) c,
      ];

/// The newest save, for a short amber highlight of its row, its quick choice and the live view.
@immutable
class RecentSave {
  const RecentSave(this.requestId, this.seconds);

  final String requestId;

  /// The quick choice used, or null for the main Save key.
  final int? seconds;
}

class RecentSaveNotifier extends Notifier<RecentSave?> {
  static const highlightFor = Duration(milliseconds: 1500);

  Timer? _timer;

  @override
  RecentSave? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void mark(String requestId, int? seconds) {
    _timer?.cancel();
    state = RecentSave(requestId, seconds);
    _timer = Timer(highlightFor, () => state = null);
  }
}

final recentSaveProvider = NotifierProvider<RecentSaveNotifier, RecentSave?>(RecentSaveNotifier.new);

/// Newest first, with filter chips by tag (and their counts) on top. On Android a resumed session
/// also lists the clips saved into it before ([liveClipsProvider]).
class ClipList extends ConsumerWidget {
  const ClipList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final clips = ref.watch(liveClipsProvider);
    final clipTags = ref.watch(clipTagsProvider);
    final inUse = tagsInUse(clips, clipTags, ref.watch(tagsProvider));
    final selected = ref.watch(clipFilterProvider);
    // A filter whose tag is no longer on any clip falls back to "All", and is cleared for good:
    // otherwise tagging a later clip would silently switch it back on.
    final filter = inUse.any((t) => t.id == selected) ? selected : null;
    if (selected != null && filter == null) {
      Future.microtask(() => ref.read(clipFilterProvider.notifier).select(null));
    }
    final shown = filterClips(clips, clipTags, filter);
    final small = TextStyle(fontSize: 13, color: c.muted);
    void select(String? id) => ref.read(clipFilterProvider.notifier).select(id);
    int count(String id) => clips.where((x) => clipTags[x.requestId] == id).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inUse.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                IrFilterChip(
                  key: const ValueKey('filter-all'),
                  label: l10n.viewerFilterAll,
                  color: c.muted,
                  count: clips.length,
                  selected: filter == null,
                  onTap: () => select(null),
                ),
                for (final t in inUse)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: IrFilterChip(
                      key: ValueKey('filter-${t.id}'),
                      label: t.label(l10n),
                      color: t.colour,
                      count: count(t.id),
                      selected: filter == t.id,
                      onTap: () => select(filter == t.id ? null : t.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: clips.isEmpty
              ? _Empty(web: kIsWeb)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                  itemCount: shown.length + (kIsWeb ? 1 : 0),
                  itemBuilder: (context, i) => i < shown.length
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _Deletable(key: ValueKey(shown[i].requestId), clip: shown[i]),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(l10n.viewerSessionOnlyNotice, style: small, textAlign: TextAlign.center),
                        ),
                ),
        ),
      ],
    );
  }
}

/// No clips yet: an icon, one line and a hint.
class _Empty extends StatelessWidget {
  const _Empty({required this.web});

  final bool web;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (box.maxHeight >= 140) ...[
                  Icon(Icons.video_library_outlined, size: 32, color: c.muted),
                  const SizedBox(height: 8),
                ],
                Text(
                  l10n.viewerClipsEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  [l10n.liveClipsEmptyHint, if (web) l10n.viewerSessionOnlyNotice].join('\n'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Swipe a finished clip to delete it; a SnackBar offers Undo before the deletion stands.
/// Clips still being requested, recorded or downloaded cannot be swiped.
class _Deletable extends ConsumerWidget {
  const _Deletable({super.key, required this.clip});

  final SessionClip clip;

  static bool canDelete(SessionClip c) => c.phase == SessionClipPhase.ready || c.phase == SessionClipPhase.failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = ClipTile(clip: clip);
    if (!canDelete(clip)) return tile;
    final c = context.ir;
    return Dismissible(
      key: ValueKey('clip-delete-${clip.requestId}'),
      direction: DismissDirection.endToStart,
      background: DecoratedBox(
        decoration: BoxDecoration(
          color: c.liveSoft,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.live),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 24),
            child: Icon(Icons.delete_outline, color: c.liveText),
          ),
        ),
      ),
      onDismissed: (_) => deleteClipWithUndo(context, ref, clip),
      child: tile,
    );
  }
}

/// Takes [clip] off the list and offers Undo; the deletion stands when the SnackBar goes away.
void deleteClipWithUndo(BuildContext context, WidgetRef ref, SessionClip clip) {
  final l10n = AppLocalizations.of(context);
  final clips = ref.read(viewerClipsProvider.notifier);
  if (!clips.delete(clip.requestId)) return;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final tag = ref.read(clipTagProvider(clip.requestId));
  messenger
      .showSnackBar(SnackBar(
        content: Text(l10n.viewerClipDeleted(clipName(l10n, tag, clip.requestedAt))),
        action: SnackBarAction(label: l10n.viewerClipUndo, onPressed: () {}),
        // A SnackBar with an action stays until dismissed by default; this one must go away so
        // the deletion stands.
        persist: false,
        duration: const Duration(seconds: 5),
      ))
      .closed
      .then((reason) => reason == SnackBarClosedReason.action
          ? clips.undoDelete(clip.requestId)
          : clips.commitDelete(clip.requestId));
}

/// One row of the cue list: thumbnail (tag-colour bar, duration badge), the tag as title, time
/// and state in mono, a visible tag button and a play button. Tap to review; long-press or the
/// tag button to change the tag. The newest save is highlighted for a moment.
class ClipTile extends ConsumerWidget {
  const ClipTile({super.key, required this.clip});

  final SessionClip clip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final tag = ref.watch(clipTagProvider(clip.requestId));
    final fresh = ref.watch(recentSaveProvider.select((r) => r?.requestId == clip.requestId));
    final (state, stateColor) = switch (clip.phase) {
      SessionClipPhase.requesting => (l10n.viewerClipRequesting, c.muted),
      SessionClipPhase.recording => (l10n.viewerClipRecording, c.muted),
      SessionClipPhase.downloading => (
          clip.progress == null || clip.received == 0
              ? l10n.viewerClipDownloadingStarted
              : l10n.viewerClipDownloading((clip.progress! * 100).round()),
          c.muted,
        ),
      SessionClipPhase.ready => (l10n.viewerClipReady, c.ok),
      SessionClipPhase.failed => (
          switch (clip.failure) {
            ClipFailure.request || null => l10n.viewerClipFailedRequest,
            ClipFailure.download => l10n.viewerClipFailedDownload,
            ClipFailure.checksum => l10n.viewerClipFailedChecksum,
            ClipFailure.expired => l10n.viewerClipExpired,
          },
          c.liveText,
        ),
    };
    final stored = clip.stored;
    void changeTag() => showClipTagPicker(context, clip.requestId);
    // While streaming, a clip still on the Camera can also go on air (SPEC §12.6).
    final VoidCallback? open = stored == null
        ? null
        : () => openClipReview(
              context,
              ref,
              clip,
              ({required onAir}) => ReviewPage.route(clip, replayBar: true, onAir: onAir),
            );
    final still = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(
      builder: (context, box) {
        final roomy = box.maxWidth >= 420;
        // Narrow panels (phone landscape) need the room for the name: the play icon sits on the
        // thumbnail instead of in its own button.
        final playButton = box.maxWidth >= 330;
        return AnimatedContainer(
          key: ValueKey('clip-row-${clip.requestId}'),
          duration: still ? Duration.zero : const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: fresh ? c.signalSoft : c.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: fresh ? c.signal : c.line),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: open,
              onLongPress: changeTag,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 4, 6),
                child: Row(
                  children: [
                    _Thumbnail(clip: clip, tag: tag, width: roomy ? 96 : (playButton ? 80 : 64), playIcon: !playButton),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tag?.label(l10n) ?? l10n.viewerClipNoTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: tag == null ? c.muted : c.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(children: [
                            Flexible(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: '${DateFormat('HH:mm').format(clip.requestedAt)} · '),
                                  TextSpan(text: state, style: TextStyle(color: stateColor)),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: irMono(12, weight: FontWeight.w500, color: c.muted),
                              ),
                            ),
                            // Still on the Camera: it can go on air (SPEC §12.6).
                            if (clip.onCamera && clip.phase == SessionClipPhase.ready) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: l10n.clipOnCamera,
                                child: Icon(
                                  Icons.videocam_outlined,
                                  key: ValueKey('clip-on-camera-${clip.requestId}'),
                                  size: 16,
                                  color: c.signal,
                                ),
                              ),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    if (clip.phase == SessionClipPhase.failed && clip.failure != ClipFailure.expired && clip.clipId != null)
                      IconButton(
                        tooltip: l10n.viewerClipRetry,
                        icon: const Icon(Icons.refresh),
                        onPressed: () => ref.read(viewerClipsProvider.notifier).retry(clip.requestId),
                      ),
                    if (roomy && stored != null && stored.canDownload)
                      IconButton(
                        tooltip: l10n.viewerClipDownload,
                        icon: const Icon(Icons.download),
                        onPressed: () => stored.download(clipFileName(clip)),
                      ),
                    IconButton(
                      key: ValueKey('clip-tag-${clip.requestId}'),
                      tooltip: l10n.viewerClipChangeTag,
                      icon: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour ?? c.muted),
                      onPressed: changeTag,
                    ),
                    if (playButton)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
                        child: Tooltip(
                          message: l10n.livePlayClip,
                          child: Material(
                            color: c.bg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                              side: BorderSide(color: c.line),
                            ),
                            child: InkWell(
                              key: ValueKey('clip-play-${clip.requestId}'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: open,
                              child: SizedBox.square(
                                dimension: 44,
                                child: Icon(Icons.play_arrow, color: open == null ? c.lineStrong : c.text),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.clip, required this.tag, required this.width, required this.playIcon});

  final SessionClip clip;
  final ViewerTag? tag;
  final double width;

  /// Draw a play icon over a finished clip (when the row has no play button).
  final bool playIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ir;
    final stored = clip.stored;
    final image = stored == null ? null : ref.watch(clipThumbnailProvider(stored)).value;
    final busy = switch (clip.phase) {
      SessionClipPhase.requesting || SessionClipPhase.recording || SessionClipPhase.downloading => true,
      _ => false,
    };
    final Widget? centre = busy
        ? SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              value: clip.phase == SessionClipPhase.downloading && clip.received > 0 ? clip.progress : null,
              strokeWidth: 3,
            ),
          )
        : clip.phase == SessionClipPhase.failed
            ? Icon(Icons.error_outline, color: c.live, size: 26)
            : playIcon || image == null
                ? Icon(Icons.play_circle, size: 26, color: image == null ? c.muted : Colors.white.withValues(alpha: 0.85))
                : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: ColoredBox(
          color: c.surfaceHigh,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null) Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true),
              if (centre != null) Center(child: centre),
              PositionedDirectional(
                end: 3,
                top: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(2)),
                  child: Text(
                    AppLocalizations.of(context).viewerClipDuration(clipSeconds(clip)),
                    style: irMono(10, weight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 3,
                child: ColoredBox(color: tag?.colour ?? c.lineStrong),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `instantreplay-20261029-153012.mp4`
String clipFileName(SessionClip clip) {
  final t = clip.requestedAt;
  String two(int v) => v.toString().padLeft(2, '0');
  return 'instantreplay-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.mp4';
}

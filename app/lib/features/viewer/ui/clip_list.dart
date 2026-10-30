import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../clips/clip_transfers.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import '../viewer_providers.dart';
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

/// Newest first, with filter chips by tag on top.
class ClipList extends ConsumerWidget {
  const ClipList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final clips = ref.watch(viewerClipsProvider);
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
    final small = Theme.of(context).textTheme.bodySmall;
    void select(String? id) => ref.read(clipFilterProvider.notifier).select(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inUse.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                ChoiceChip(
                  key: const ValueKey('filter-all'),
                  label: Text(l10n.viewerFilterAll),
                  selected: filter == null,
                  onSelected: (_) => select(null),
                ),
                for (final t in inUse)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: ChoiceChip(
                      key: ValueKey('filter-${t.id}'),
                      avatar: Icon(Icons.circle, size: 14, color: t.colour),
                      label: Text(t.label(l10n)),
                      selected: filter == t.id,
                      onSelected: (_) => select(filter == t.id ? null : t.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: clips.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      [l10n.viewerClipsEmpty, if (kIsWeb) l10n.viewerSessionOnlyNotice].join('\n'),
                      style: small,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: shown.length + (kIsWeb ? 1 : 0),
                  itemBuilder: (context, i) => i < shown.length
                      ? ClipTile(key: ValueKey(shown[i].requestId), clip: shown[i])
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

/// Thumbnail, name (tag + time), duration, tag colour and state. Tap to review; long-press or the
/// tag button to change the tag.
class ClipTile extends ConsumerWidget {
  const ClipTile({super.key, required this.clip});

  final SessionClip clip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tag = ref.watch(clipTagProvider(clip.requestId));
    final (state, stateColor) = switch (clip.phase) {
      SessionClipPhase.requesting => (l10n.viewerClipRequesting, null),
      SessionClipPhase.recording => (l10n.viewerClipRecording, null),
      SessionClipPhase.downloading => (
          clip.progress == null || clip.received == 0
              ? l10n.viewerClipDownloadingStarted
              : l10n.viewerClipDownloading((clip.progress! * 100).round()),
          null,
        ),
      SessionClipPhase.ready => (l10n.viewerClipReady, scheme.primary),
      SessionClipPhase.failed => (
          switch (clip.failure) {
            ClipFailure.request || null => l10n.viewerClipFailedRequest,
            ClipFailure.download => l10n.viewerClipFailedDownload,
            ClipFailure.checksum => l10n.viewerClipFailedChecksum,
            ClipFailure.expired => l10n.viewerClipExpired,
          },
          scheme.error,
        ),
    };
    final stored = clip.stored;
    void changeTag() => showClipTagPicker(context, clip.requestId);
    return LayoutBuilder(
      builder: (context, c) {
        final roomy = c.maxWidth >= 420;
        return InkWell(
          onTap: stored == null ? null : () => Navigator.of(context).push(ReviewPage.route(clip)),
          onLongPress: changeTag,
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              border: BorderDirectional(start: BorderSide(color: tag?.colour ?? Colors.transparent, width: 5)),
            ),
            padding: const EdgeInsetsDirectional.only(start: 7, end: 4),
            child: Row(
              children: [
                // Narrow panels (phone landscape) need the room for the name.
                _Thumbnail(clip: clip, width: roomy ? 96 : 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clipName(l10n, tag, clip.requestedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${l10n.viewerClipDuration(clipSeconds(clip))} · $state',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: stateColor),
                      ),
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
                  icon: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour),
                  onPressed: changeTag,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.clip, required this.width});

  final SessionClip clip;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stored = clip.stored;
    final image = stored == null ? null : ref.watch(clipThumbnailProvider(stored)).value;
    final busy = switch (clip.phase) {
      SessionClipPhase.requesting || SessionClipPhase.recording || SessionClipPhase.downloading => true,
      _ => false,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null) Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true),
              Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(
                          value: clip.phase == SessionClipPhase.downloading && clip.received > 0 ? clip.progress : null,
                          strokeWidth: 3,
                        ),
                      )
                    : clip.phase == SessionClipPhase.failed
                        ? Icon(Icons.error_outline, color: scheme.error, size: 28)
                        : Icon(
                            Icons.play_circle,
                            size: 28,
                            color: image == null ? scheme.onSurfaceVariant : Colors.white.withValues(alpha: 0.85),
                          ),
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

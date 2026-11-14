import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/capabilities.dart';
import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewer/clips/clip_batch_export.dart';
import '../../viewer/clips/clip_export.dart';
import '../../viewer/tags/tags.dart';
import '../../viewer/ui/clip_list.dart';
import '../../viewer/ui/playlist_page.dart';
import '../../viewer/ui/review_page.dart';
import '../data/library_database.dart';
import '../labels.dart';
import '../library_providers.dart';
import 'templates_page.dart';

/// Library (SPEC §5.1.6), Android: sessions, newest first, filtered by kind. Tap to see the clips;
/// long-press to delete.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const LibraryPage());

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// Null shows every session; "other" sessions show only there.
  SessionType? _kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(librarySessionsProvider);
    final kinds = <(SessionType?, String)>[
      (null, l10n.libFilterAll),
      (SessionType.match, l10n.libFilterMatches),
      (SessionType.training, l10n.libFilterTrainings),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: [
          IconButton(
            tooltip: l10n.libraryTemplatesTitle,
            icon: const Icon(Icons.sell_outlined),
            onPressed: () => Navigator.of(context).push(TemplatesPage.route()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: switch (sessions) {
              AsyncData(value: final list) when list.isEmpty => _EmptyState(
                  icon: Icons.video_library_outlined,
                  title: l10n.libraryEmpty,
                  message: l10n.libEmptyHint,
                ),
              AsyncData(value: final list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(children: [
                      for (final (i, (kind, label)) in kinds.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        IrFilterChip(
                          key: ValueKey('library-kind-${kind?.name ?? 'all'}'),
                          label: label,
                          count: kind == null ? list.length : list.where((s) => s.session.type == kind).length,
                          selected: _kind == kind,
                          onTap: () => setState(() => _kind = kind),
                        ),
                      ],
                    ]),
                  ),
                  Expanded(child: _sessionList(context, [
                    for (final s in list)
                      if (_kind == null || s.session.type == _kind) s,
                  ])),
                ]),
              AsyncError(:final error) => _EmptyState(
                  icon: Icons.error_outline,
                  title: l10n.libError,
                  message: '$error',
                  action: (l10n.libRetry, () => ref.invalidate(librarySessionsProvider)),
                  danger: true,
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }

  Widget _sessionList(BuildContext context, List<SessionSummary> shown) {
    final l10n = AppLocalizations.of(context);
    if (shown.isEmpty) {
      return _EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: l10n.libFilterEmpty,
        action: (l10n.libFilterAll, () => setState(() => _kind = null)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = shown[i];
        return _SessionPanel(
          key: ValueKey('session-${s.session.id}'),
          summary: s,
          onTap: () => Navigator.of(context).push(SessionClipsPage.route(s.session)),
          onLongPress: () => _confirmDeleteSession(context, ref, s.session),
        );
      },
    );
  }
}

/// A session: name and clip count, then kind and date.
class _SessionPanel extends StatelessWidget {
  const _SessionPanel({super.key, required this.summary, required this.onTap, required this.onLongPress});

  final SessionSummary summary;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final s = summary.session;
    final radius = BorderRadius.circular(6);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(
                switch (s.type) {
                  SessionType.match => Icons.sports,
                  SessionType.training => Icons.fitness_center,
                  SessionType.other => Icons.video_library_outlined,
                },
                color: c.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Expanded(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.librarySessionClips(summary.clipCount),
                      style: irMono(14, weight: FontWeight.w600, color: summary.clipCount == 0 ? c.muted : c.text),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '${sessionTypeLabel(l10n, s.type)} · ${DateFormat.MMMd(l10n.localeName).add_Hm().format(s.startedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.muted),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: c.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Empty, filtered-out and error states: an icon, a line of text and, maybe, a way out.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.message, this.action, this.danger = false});

  final IconData icon;
  final String title;
  final String? message;
  final (String, VoidCallback)? action;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: danger ? c.liveText : c.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
          if (message case final message?) ...[
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.muted)),
          ],
          if (action case (final label, final onPressed)) ...[
            const SizedBox(height: 16),
            OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)), onPressed: onPressed, child: Text(label)),
          ],
        ]),
      ),
    );
  }
}

Future<void> _confirmDeleteSession(BuildContext context, WidgetRef ref, SessionRow session) async {
  final l10n = AppLocalizations.of(context);
  final ok = await _confirm(context, l10n.libraryDeleteSessionConfirm(session.name), l10n.libraryDeleteSession);
  if (ok) await deleteLibrarySession(ref.read, session.id);
}

Future<bool> _confirm(BuildContext context, String message, String action) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.viewerTagCancel)),
        FilledButton(
          key: const ValueKey('confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The clips of one session, newest first, in a grid, with a count per tag that doubles as the
/// tag filter. "Select" (or a long-press) starts selecting for a batch export or delete.
class SessionClipsPage extends ConsumerStatefulWidget {
  const SessionClipsPage({super.key, required this.session});

  final SessionRow session;

  static Route<void> route(SessionRow session) =>
      MaterialPageRoute<void>(builder: (_) => SessionClipsPage(session: session));

  @override
  ConsumerState<SessionClipsPage> createState() => _SessionClipsPageState();
}

class _SessionClipsPageState extends ConsumerState<SessionClipsPage> {
  String? _tag;
  final _selected = <String>{};

  /// Selecting from the "Select" button, even with nothing picked yet.
  bool _selectMode = false;
  bool _exporting = false;

  bool get _selecting => _selectMode || _selected.isNotEmpty;

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _endSelection() => setState(() {
    _selected.clear();
    _selectMode = false;
  });

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final ids = {..._selected};
    final ok = await _confirm(context, l10n.libraryDeleteClipsConfirm(ids.length), l10n.libraryDelete);
    if (!ok) return;
    await deleteLibraryClips(ref.read, ids);
    if (mounted) _endSelection();
  }

  /// Shows only clips tagged [tag] (all when null); a selection keeps only the clips still shown.
  void _filter(String? tag, List<ClipEntry> clips) => setState(() {
    _tag = tag;
    if (tag != null) {
      _selected.removeWhere((id) => !clips.any((e) => e.clip.id == id && e.tagIds.contains(tag)));
    }
  });

  /// Exports the selected clips, oldest first: joined into one video (gallery or share) or as a
  /// ZIP. Without [choice], asks which.
  Future<void> _exportSelected(List<ClipEntry> clips, Map<String, ViewerTag> labels, {int? choice}) async {
    final l10n = AppLocalizations.of(context);
    choice ??= await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text(l10n.libraryExportJoinedGallery),
              onTap: () => Navigator.of(context).pop(0),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l10n.libraryExportJoinedShare),
              onTap: () => Navigator.of(context).pop(1),
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(l10n.libraryExportZip),
              onTap: () => Navigator.of(context).pop(2),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final picked = [
      for (final e in clips)
        if (_selected.contains(e.clip.id)) e,
    ]..sort((a, b) => a.clip.requestedAt.compareTo(b.clip.requestedAt));
    if (picked.isEmpty) return;
    final batch = [
      for (final e in picked)
        (
          path: e.clip.filePath,
          name:
              '${_safeName(e.clip.title ?? clipName(l10n, e.tagIds.map((id) => labels[id]).nonNulls.firstOrNull, e.clip.requestedAt))}.mp4',
        ),
    ];
    // All of one tag: name the file after the session and that tag.
    final pickedTags = {for (final e in picked) e.tagIds.firstOrNull};
    final onlyTag = pickedTags.length == 1 ? labels[pickedTags.single] : null;
    final base = _safeName([widget.session.name, ?onlyTag?.label(l10n)].join(' - '));
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    messenger.showSnackBar(SnackBar(content: Text(l10n.libraryExporting), duration: const Duration(minutes: 5)));
    final result = await switch (choice) {
      0 => ClipBatchExport.joined(batch, '$base.mp4', share: false),
      1 => ClipBatchExport.joined(batch, '$base.mp4', share: true),
      _ => ClipBatchExport.zip(batch, '$base.zip'),
    };
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    setState(() => _exporting = false);
    final message = switch (result) {
      ClipExportResult.done => choice == 0 ? l10n.viewerClipSavedToGallery : null,
      ClipExportResult.denied => l10n.viewerClipGalleryDenied,
      ClipExportResult.noSpace => l10n.viewerClipExportNoSpace,
      ClipExportResult.failed => l10n.viewerClipExportFailed,
    };
    if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Plays [entries] one after another, oldest first, with their tags seeded as in [_open].
  Future<void> _watchAll(List<ClipEntry> entries, Map<String, ViewerTag> labels) async {
    if (entries.isEmpty) return;
    final choices = await libraryLabelChoices(ref.read, widget.session.id);
    if (!mounted) return;
    ref.read(knownLabelsProvider.notifier).addAll({
      ...labels,
      for (final l in [...?choices?.tags]) l.id: l,
    });
    final ordered = [...entries]..sort((a, b) => a.clip.requestedAt.compareTo(b.clip.requestedAt));
    final clips = [for (final e in ordered) sessionClipFromEntry(e)];
    final tags = ref.read(clipTagsProvider.notifier);
    for (final (i, e) in ordered.indexed) {
      tags.set(clips[i].requestId, e.tagIds.firstOrNull);
    }
    await Navigator.of(context).push(PlaylistPage.route(clips, labelChoices: choices));
  }

  /// Opens the review with the clip's tag seeded, so it shows and changes are saved back. Its tag
  /// picker offers the tags of this session's template.
  Future<void> _open(ClipEntry e, Map<String, ViewerTag> labels) async {
    final choices = await libraryLabelChoices(ref.read, widget.session.id);
    if (!mounted) return;
    ref.read(knownLabelsProvider.notifier).addAll({
      ...labels,
      for (final l in [...?choices?.tags]) l.id: l,
    });
    final clip = sessionClipFromEntry(e);
    ref.read(clipTagsProvider.notifier).set(clip.requestId, e.tagIds.firstOrNull);
    await Navigator.of(context).push(ReviewPage.route(labelChoices: choices, clip));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    // Keeps tag changes made in the review flowing back into the library.
    ref.watch(clipLabelWriterProvider);
    final loaded = ref.watch(sessionClipsProvider(widget.session.id));
    final clips = loaded.value ?? const <ClipEntry>[];
    final labels = ref.watch(libraryLabelsProvider).value ?? const <String, ViewerTag>{};
    final counts = <String, int>{};
    for (final e in clips) {
      for (final id in e.tagIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final tags = [for (final id in counts.keys) ?labels[id]];
    final shown = [
      for (final e in clips)
        if (_tag == null || e.tagIds.contains(_tag)) e,
    ];
    final selecting = _selecting;
    final canShare = ref.watch(capabilitiesProvider).canShare;

    final Widget body;
    if (loaded case AsyncError(:final error) when clips.isEmpty) {
      body = _EmptyState(
        icon: Icons.error_outline,
        title: l10n.libError,
        message: '$error',
        action: (l10n.libRetry, () => ref.invalidate(sessionClipsProvider(widget.session.id))),
        danger: true,
      );
    } else if (loaded.isLoading && !loaded.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (clips.isEmpty) {
      body = _EmptyState(icon: Icons.movie_outlined, title: l10n.librarySessionClipsEmpty, message: l10n.libEmptyHint);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 82,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            children: [
              _TagTile(
                key: const ValueKey('library-filter-all'),
                label: l10n.viewerFilterAll,
                count: clips.length,
                color: c.lineStrong,
                selected: _tag == null,
                onTap: () => _filter(null, clips),
              ),
              for (final t in tags) ...[
                const SizedBox(width: 6),
                _TagTile(
                  key: ValueKey('library-filter-${t.id}'),
                  label: t.label(l10n),
                  count: counts[t.id] ?? 0,
                  color: t.colour,
                  selected: _tag == t.id,
                  onTap: () => _filter(_tag == t.id ? null : t.id, clips),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            const pad = 14.0, gap = 8.0;
            final columns = ((box.maxWidth - 2 * pad + gap) / 228).floor().clamp(2, 6);
            final tileWidth = (box.maxWidth - 2 * pad - gap * (columns - 1)) / columns;
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(pad, 10, pad, 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: tileWidth * 9 / 16 + 3 + 58,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final e = shown[i];
                final id = e.clip.id;
                return _ClipCard(
                  key: ValueKey('library-clip-$id'),
                  entry: e,
                  tag: e.tagIds.map((id) => labels[id]).nonNulls.firstOrNull,
                  selecting: selecting,
                  selected: _selected.contains(id),
                  onTap: selecting ? () => _toggle(id) : () => _open(e, labels),
                  onLongPress: () => _toggle(id),
                );
              },
            );
          }),
        ),
      ]);
    }

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            selecting ? l10n.librarySelected(_selected.length) : widget.session.name,
            overflow: TextOverflow.ellipsis,
          ),
          leading: selecting ? IconButton(icon: const Icon(Icons.close), onPressed: _endSelection) : null,
          actions: [
            // Watch all: exactly what the grid shows (the tag filter applies), or the selection.
            if (shown.isNotEmpty && (!selecting || _selected.isNotEmpty))
              IconButton(
                key: const ValueKey('library-watch-all'),
                tooltip: l10n.libraryWatchAll(selecting ? _selected.length : shown.length),
                icon: const Icon(Icons.playlist_play),
                onPressed: () => _watchAll([
                  for (final e in shown)
                    if (!selecting || _selected.contains(e.clip.id)) e,
                ], labels),
              ),
            if (selecting)
              IconButton(
                tooltip: l10n.librarySelectAll,
                icon: const Icon(Icons.select_all),
                onPressed: () => setState(
                  () => _selected
                    ..clear()
                    ..addAll([for (final e in shown) e.clip.id]),
                ),
              )
            else ...[
              if (clips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    key: const ValueKey('library-select'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: c.lineStrong),
                    ),
                    onPressed: () => setState(() => _selectMode = true),
                    child: Text(l10n.libSelect),
                  ),
                ),
              IconButton(
                tooltip: l10n.libraryDeleteSession,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    l10n.libraryDeleteSessionConfirm(widget.session.name),
                    l10n.libraryDeleteSession,
                  );
                  if (!ok) return;
                  await deleteLibrarySession(ref.read, widget.session.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ],
        ),
        body: SafeArea(bottom: !selecting || _selected.isEmpty, child: body),
        bottomNavigationBar: selecting && _selected.isNotEmpty
            ? _SelectionBar(
                count: _selected.length,
                exporting: _exporting,
                onExport: canShare ? () => _exportSelected(clips, labels) : null,
                onShare: canShare ? () => _exportSelected(clips, labels, choice: 1) : null,
                onDelete: _deleteSelected,
              )
            : null,
      ),
    );
  }
}

/// A tag with its clip count; tap to show only its clips.
class _TagTile extends StatelessWidget {
  const _TagTile({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.signalSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: selected ? c.signal : c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 84),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: color, width: 3))),
            padding: const EdgeInsets.fromLTRB(10, 4, 12, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('$count', style: irMono(22, color: c.text, height: 1.15)),
              Text(label, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A clip in the grid: a tag-coloured panel (library clips have no thumbnail on Android), its
/// name, duration and time, and a checkbox while selecting.
class _ClipCard extends StatelessWidget {
  const _ClipCard({
    super.key,
    required this.entry,
    required this.tag,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ClipEntry entry;
  final ViewerTag? tag;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final clip = entry.clip;
    final tagColor = tag?.colour ?? c.lineStrong;
    final seconds = ((clip.durationMs ?? 0) / 1000).round();
    return Semantics(
      selected: selecting ? selected : null,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: selected ? c.signal : c.line, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(
                  color: Color.alphaBlend(tagColor.withValues(alpha: 0.28), c.surfaceHigh),
                  child: Icon(Icons.play_circle_outline, size: 36, color: c.text.withValues(alpha: 0.8)),
                ),
                if (selecting)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? c.signal : c.bg.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: selected ? c.signal : c.text, width: 2),
                      ),
                      child: selected ? Icon(Icons.check, size: 18, color: c.onSignal) : null,
                    ),
                  ),
              ]),
            ),
            Container(height: 3, color: tagColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  clip.title ?? clipName(l10n, tag, clip.requestedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                ),
                Text(
                  '${l10n.viewerClipDuration(seconds)} · ${DateFormat.Hms(l10n.localeName).format(clip.requestedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: irMono(12, weight: FontWeight.w500, color: c.muted),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// What to do with the selected clips: export (asks how), share as one video, delete.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.exporting,
    required this.onExport,
    required this.onShare,
    required this.onDelete,
  });

  final int count;
  final bool exporting;
  final VoidCallback? onExport;
  final VoidCallback? onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    // Three buttons share a phone's width: little side padding so the labels fit.
    const tight = EdgeInsets.symmetric(horizontal: 8);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.lineStrong))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            if (onExport != null) ...[
              Expanded(
                flex: 14,
                child: FilledButton(
                  key: const ValueKey('library-export-selected'),
                  style: FilledButton.styleFrom(padding: tight),
                  onPressed: exporting ? null : onExport,
                  child: exporting
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.libExportCount(count), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (onShare != null) ...[
              Expanded(
                flex: 10,
                child: OutlinedButton(
                  key: const ValueKey('library-share-selected'),
                  style: OutlinedButton.styleFrom(padding: tight),
                  onPressed: exporting ? null : onShare,
                  child: Text(l10n.libShare, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 10,
              child: OutlinedButton(
                key: const ValueKey('library-delete-selected'),
                style: OutlinedButton.styleFrom(foregroundColor: c.liveText, side: BorderSide(color: c.live), padding: tight),
                onPressed: onDelete,
                child: Text(l10n.libraryDelete, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A file name without characters Android or ZIP tools reject.
String _safeName(String name) {
  final s = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), ' ').trim();
  return s.isEmpty ? 'instantreplay' : s;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../viewer/clips/clip_store.dart';
import '../../viewer/clips/clip_transfers.dart';
import '../../viewer/tags/tags.dart';
import '../../viewer/ui/clip_list.dart';
import '../../viewer/ui/review_page.dart';
import '../data/library_database.dart';
import '../library_providers.dart';
import 'session_picker_view.dart';
import 'templates_page.dart';

/// Library (SPEC §5.1.6), Android: sessions, newest first. Tap to see the clips; long-press to delete.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const LibraryPage());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(librarySessionsProvider);
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
        child: switch (sessions) {
          AsyncData(value: final list) when list.isEmpty => Center(child: Text(l10n.libraryEmpty)),
          AsyncData(value: final list) => ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final s = list[i];
                return ListTile(
                  key: ValueKey('session-${s.session.id}'),
                  minTileHeight: 72,
                  leading: Icon(switch (s.session.type) {
                    SessionType.match => Icons.sports,
                    SessionType.training => Icons.fitness_center,
                    SessionType.other => Icons.video_library_outlined,
                  }),
                  title: Text(s.session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(sessionSubtitle(l10n, s)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(SessionClipsPage.route(s.session)),
                  onLongPress: () => _confirmDeleteSession(context, ref, s.session),
                );
              },
            ),
          AsyncError(:final error) => Center(child: Text('$error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
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

/// The clips of one session, newest first, with filter chips by tag. Long-press starts selecting
/// for a batch delete.
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

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final ids = {..._selected};
    final ok = await _confirm(context, l10n.libraryDeleteClipsConfirm(ids.length), l10n.libraryDelete);
    if (!ok) return;
    await deleteLibraryClips(ref.read, ids);
    if (mounted) setState(_selected.clear);
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
    final c = e.clip;
    final key = c.requestId ?? c.id;
    ref.read(clipTagsProvider.notifier).set(key, e.tagIds.firstOrNull);
    await Navigator.of(context).push(ReviewPage.route(labelChoices: choices, SessionClip(
      requestId: key,
      seconds: (c.durationMs ?? 0) / 1000,
      requestedAt: c.requestedAt,
      phase: SessionClipPhase.ready,
      clipId: c.id,
      durationMs: c.durationMs,
      received: c.sizeBytes,
      total: c.sizeBytes,
      stored: ClipStore.openFile(c.id, c.filePath, c.sizeBytes),
      acked: true,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Keeps tag changes made in the review flowing back into the library.
    ref.watch(clipLabelWriterProvider);
    final clips = ref.watch(sessionClipsProvider(widget.session.id)).value ?? const <ClipEntry>[];
    final labels = ref.watch(libraryLabelsProvider).value ?? const <String, ViewerTag>{};
    final usedTags = {for (final e in clips) ...e.tagIds};
    final tags = [for (final id in usedTags) ?labels[id]];
    final shown = [
      for (final e in clips)
        if (_tag == null || e.tagIds.contains(_tag)) e,
    ];
    final selecting = _selected.isNotEmpty;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selecting ? l10n.librarySelected(_selected.length) : widget.session.name),
          leading: selecting ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)) : null,
          actions: [
            if (selecting) ...[
              IconButton(
                tooltip: l10n.librarySelectAll,
                icon: const Icon(Icons.select_all),
                onPressed: () => setState(() => _selected.addAll([for (final e in shown) e.clip.id])),
              ),
              IconButton(
                key: const ValueKey('library-delete-selected'),
                tooltip: l10n.libraryDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteSelected,
              ),
            ] else
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
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tags.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    children: [
                      ChoiceChip(
                        key: const ValueKey('library-filter-all'),
                        label: Text(l10n.viewerFilterAll),
                        selected: _tag == null,
                        onSelected: (_) => setState(() => _tag = null),
                      ),
                      for (final t in tags)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8),
                          child: ChoiceChip(
                            key: ValueKey('library-filter-${t.id}'),
                            avatar: Icon(Icons.circle, size: 14, color: t.colour),
                            label: Text(t.label(l10n)),
                            selected: _tag == t.id,
                            onSelected: (_) => setState(() => _tag = _tag == t.id ? null : t.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: clips.isEmpty
                    ? Center(child: Text(l10n.librarySessionClipsEmpty))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final e = shown[i];
                          final c = e.clip;
                          final tag = e.tagIds.map((id) => labels[id]).nonNulls.firstOrNull;
                          final selected = _selected.contains(c.id);
                          final seconds = ((c.durationMs ?? 0) / 1000).round();
                          return ListTile(
                            key: ValueKey('library-clip-${c.id}'),
                            minTileHeight: 72,
                            selected: selected,
                            leading: selecting
                                ? Checkbox(value: selected, onChanged: (_) => _toggle(c.id))
                                : Container(
                                    width: 6,
                                    color: tag?.colour ?? Colors.transparent,
                                  ),
                            title: Text(
                              c.title ?? clipName(l10n, tag, c.requestedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                l10n.viewerClipDuration(seconds),
                                DateFormat.Hms(l10n.localeName).format(c.requestedAt),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selecting ? null : const Icon(Icons.play_circle_outline),
                            onTap: selecting ? () => _toggle(c.id) : () => _open(e, labels),
                            onLongPress: () => _toggle(c.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

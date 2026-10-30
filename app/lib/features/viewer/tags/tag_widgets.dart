import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'tag_editor_page.dart';
import 'tags.dart';

/// One tag as a tappable button with its colour.
class TagButton extends StatelessWidget {
  const TagButton({super.key, required this.tag, required this.onPressed, this.selected = false, this.large = false});

  final ViewerTag tag;
  final VoidCallback onPressed;
  final bool selected;

  /// Bigger target and text, for the post-save panel.
  final bool large;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: ValueKey('tag-${tag.id}'),
        style: OutlinedButton.styleFrom(
          minimumSize: large ? const Size(112, 56) : const Size(72, 48),
          padding: large ? const EdgeInsets.symmetric(horizontal: 20) : null,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: tag.colour, width: selected ? 3 : 1.5),
          backgroundColor: selected ? tag.colour.withValues(alpha: 0.25) : null,
        ),
        onPressed: onPressed,
        icon: Icon(Icons.circle, size: large ? 18 : 14, color: tag.colour),
        label: Text(
          tag.label(AppLocalizations.of(context)),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: large ? 18 : null),
        ),
      );
}

/// Sheet to choose the tag of clip [requestId] (or none). [choices] replaces the active session's
/// labels for a clip of another session (library review); that template is not editable from here.
Future<void> showClipTagPicker(BuildContext context, String requestId, {ClipLabelChoices? choices}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final l10n = AppLocalizations.of(context);
          final List<ViewerTag> tags = choices?.tags ?? ref.watch(tagsProvider);
          final current = ref.watch(clipTagsProvider.select((m) => m[requestId]));
          final List<ViewerTag> categories = choices?.categories ?? ref.watch(categoriesProvider);
          final category = ref.watch(clipCategoriesProvider.select((m) => m[requestId]));
          void set(String? id) {
            ref.read(clipTagsProvider.notifier).set(requestId, id);
            Navigator.of(context).pop();
          }

          // Scrolls when a big template does not fit (a phone in landscape).
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Android library: the category stays open for a tag to follow.
                  if (categories.isNotEmpty) ...[
                    Text(l10n.libraryCategory, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in categories)
                          TagButton(
                            tag: c,
                            selected: c.id == category,
                            onPressed: () => ref
                                .read(clipCategoriesProvider.notifier)
                                .set(requestId, c.id == category ? null : c.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(l10n.viewerClipChangeTag, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tags) TagButton(tag: t, selected: t.id == current, onPressed: () => set(t.id)),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(72, 48)),
                        onPressed: () => set(null),
                        icon: const Icon(Icons.label_off_outlined),
                        label: Text(l10n.viewerClipNoTag),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (choices == null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(TagEditorPage.route());
                        },
                        icon: const Icon(Icons.edit),
                        label: Text(l10n.viewerTagsEdit),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

/// After a save, a panel slides in from the left over the live view for [PostSaveTagBarNotifier.visibleFor]
/// with large buttons for the clip's category and tag (UX §3.2). The buttons wrap freely over the
/// whole panel, so long tag sets need no sideways scrolling; Save and the quick chips stay free for
/// the next play. Picking a tag (or the close button) hides it; picking a category keeps it up a
/// little longer for the tag.
class PostSaveTagPanel extends ConsumerWidget {
  const PostSaveTagPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestId = ref.watch(postSaveTagBarProvider);
    final tags = ref.watch(tagsProvider);
    final categories = ref.watch(categoriesProvider);
    final show = requestId != null && (tags.isNotEmpty || categories.isNotEmpty);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      child: show ? _Panel(key: ValueKey(requestId), requestId: requestId, tags: tags, categories: categories) : null,
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({super.key, required this.requestId, required this.tags, required this.categories});

  final String requestId;
  final List<ViewerTag> tags;
  final List<ViewerTag> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bar = ref.read(postSaveTagBarProvider.notifier);
    final category = ref.watch(clipCategoriesProvider.select((m) => m[requestId]));
    Widget section(IconData icon, String title, List<Widget> buttons) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          ],
        );

    return Material(
      key: const ValueKey('viewer-tag-panel'),
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.96),
      borderRadius: const BorderRadiusDirectional.horizontal(end: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Time left before the panel goes away.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: PostSaveTagBarNotifier.visibleFor,
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 3),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 0),
            child: Row(children: [
              Expanded(child: Text(l10n.viewerTagPanelTitle, style: theme.textTheme.titleLarge)),
              IconButton(
                key: const ValueKey('viewer-tag-panel-close'),
                tooltip: l10n.viewerTagPanelClose,
                icon: const Icon(Icons.close),
                onPressed: bar.dismiss,
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('viewer-tag-bar'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Android library: the template's categories first (one per clip), then its tags.
                  if (categories.isNotEmpty) ...[
                    section(Icons.category_outlined, l10n.libraryCategory, [
                      for (final c in categories)
                        TagButton(tag: c, large: true, selected: c.id == category, onPressed: () => bar.pickCategory(c.id)),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  if (tags.isNotEmpty)
                    section(Icons.sell_outlined, l10n.viewerClipChangeTag, [
                      for (final t in tags) TagButton(tag: t, large: true, onPressed: () => bar.pick(t.id)),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'tag_editor_page.dart';
import 'tags.dart';

/// One tag as a tappable button with its colour.
class TagButton extends StatelessWidget {
  const TagButton({super.key, required this.tag, required this.onPressed, this.selected = false});

  final ViewerTag tag;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: ValueKey('tag-${tag.id}'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: tag.colour, width: selected ? 3 : 1.5),
          backgroundColor: selected ? tag.colour.withValues(alpha: 0.25) : null,
        ),
        onPressed: onPressed,
        icon: Icon(Icons.circle, size: 14, color: tag.colour),
        label: Text(tag.label(AppLocalizations.of(context)), style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}

/// Sheet to choose the tag of clip [requestId] (or none).
Future<void> showClipTagPicker(BuildContext context, String requestId) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final l10n = AppLocalizations.of(context);
          final tags = ref.watch(tagsProvider);
          final current = ref.watch(clipTagsProvider.select((m) => m[requestId]));
          final categories = ref.watch(categoriesProvider);
          final category = ref.watch(clipCategoriesProvider.select((m) => m[requestId]));
          void set(String? id) {
            ref.read(clipTagsProvider.notifier).set(requestId, id);
            Navigator.of(context).pop();
          }

          return SafeArea(
            child: Padding(
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

/// The slot under the save chips: the save hint normally, the tag bar for ~6 s after a save
/// (UX §3.2). Fixed height, so it never pushes the live view or the Save button around.
class PostSaveTagBar extends ConsumerWidget {
  const PostSaveTagBar({super.key, required this.idle});

  static const height = 56.0;

  /// Shown when no save is being offered for tagging.
  final Widget idle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestId = ref.watch(postSaveTagBarProvider);
    final tags = ref.watch(tagsProvider);
    final categories = ref.watch(categoriesProvider);
    final category = requestId == null ? null : ref.watch(clipCategoriesProvider.select((m) => m[requestId]));
    final Widget child;
    if (requestId == null || (tags.isEmpty && categories.isEmpty)) {
      child = Center(key: const ValueKey('idle'), child: idle);
    } else {
      child = Column(
        key: ValueKey(requestId),
        children: [
          Expanded(
            child: ListView(
              key: const ValueKey('viewer-tag-bar'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              children: [
                // Android library: the template's categories first (one per clip), then its tags.
                if (categories.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.category_outlined, size: 20)),
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TagButton(
                        tag: c,
                        selected: c.id == category,
                        onPressed: () => ref.read(postSaveTagBarProvider.notifier).pickCategory(c.id),
                      ),
                    ),
                  const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                ],
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.sell_outlined, size: 20)),
                for (final t in tags)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TagButton(tag: t, onPressed: () => ref.read(postSaveTagBarProvider.notifier).pick(t.id)),
                  ),
              ],
            ),
          ),
          // Time left before the bar fades.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: PostSaveTagBarNotifier.visibleFor,
            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 2),
          ),
        ],
      );
    }
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child),
    );
  }
}

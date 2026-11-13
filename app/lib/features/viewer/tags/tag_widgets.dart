import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import 'tag_editor_page.dart';
import 'tags.dart';

/// One tag as a tappable bordered button with its colour square. Selected: amber border and
/// fill, like every selection in the app.
class TagButton extends StatelessWidget {
  const TagButton({super.key, required this.tag, required this.onPressed, this.selected = false, this.large = false});

  final ViewerTag tag;
  final VoidCallback onPressed;
  final bool selected;

  /// Bigger target and text.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Semantics(
      selected: selected,
      child: Material(
        key: ValueKey('tag-${tag.id}'),
        color: selected ? c.signalSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: selected ? c.signal : c.lineStrong, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: large ? 56 : 48, minWidth: large ? 112 : 72),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: large ? 18 : 14),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ColourBar(colour: tag.colour, width: 6, height: large ? 24 : 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    tag.label(AppLocalizations.of(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: large ? 18 : 16, color: c.text),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tag's colour as a small glowing bar (the "LED" of a tag key).
class _ColourBar extends StatelessWidget {
  const _ColourBar({required this.colour, required this.width, required this.height});

  final Color colour;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(1),
          boxShadow: [BoxShadow(color: colour.withValues(alpha: 0.7), blurRadius: 8)],
        ),
      );
}

/// Sheet to choose the tag of clip [requestId] (or none). [choices] replaces the active session's
/// tags for a clip of another session (library review); that template is not editable from here.
Future<void> showClipTagPicker(BuildContext context, String requestId, {ClipLabelChoices? choices}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final l10n = AppLocalizations.of(context);
          final c = context.ir;
          final List<ViewerTag> tags = choices?.tags ?? ref.watch(tagsProvider);
          final current = ref.watch(clipTagsProvider.select((m) => m[requestId]));
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
                  Text(l10n.viewerClipChangeTag, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tags) TagButton(tag: t, selected: t.id == current, onPressed: () => set(t.id)),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(72, 48),
                          side: BorderSide(color: current == null ? c.signal : c.lineStrong, width: current == null ? 2 : 1),
                          backgroundColor: current == null ? c.signalSoft : null,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: () => set(null),
                        icon: Icon(Icons.label_off_outlined, color: c.muted),
                        label: Text(l10n.viewerClipNoTag),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (choices == null)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
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

/// After a save, a panel over the live view for [PostSaveTagBarNotifier.visibleFor] with an amber
/// countdown and one key per tag (UX §3.2). [dropDown] (phone portrait): it drops from the top
/// of the live view; otherwise it slides in at its bottom-left corner. The keys wrap over the
/// panel and it scrolls, so long tag sets need no sideways scrolling; Save and the quick choices
/// stay free for the next play. Picking a tag (or "No tag") hides it.
class PostSaveTagPanel extends ConsumerWidget {
  const PostSaveTagPanel({super.key, this.dropDown = false});

  final bool dropDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestId = ref.watch(postSaveTagBarProvider);
    final tags = ref.watch(tagsProvider);
    final show = requestId != null && tags.isNotEmpty;
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: dropDown ? const Offset(0, -0.08) : const Offset(-0.06, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: dropDown ? AlignmentDirectional.topStart : AlignmentDirectional.bottomStart,
        children: [...previous, ?current],
      ),
      child: show ? _Panel(key: ValueKey(requestId), tags: tags) : null,
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({super.key, required this.tags});

  final List<ViewerTag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final bar = ref.read(postSaveTagBarProvider.notifier);
    return Material(
      key: const ValueKey('viewer-tag-panel'),
      color: c.surface.withValues(alpha: 0.97),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: c.lineStrong)),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      shadowColor: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Time left before the panel goes away.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: PostSaveTagBarNotifier.visibleFor,
            builder: (_, v, _) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(widthFactor: v, child: Container(height: 3, color: c.signal)),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  l10n.liveTagPanelTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                key: const ValueKey('viewer-tag-panel-close'),
                style: TextButton.styleFrom(foregroundColor: c.muted),
                onPressed: bar.dismiss,
                child: Text(l10n.viewerClipNoTag, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('viewer-tag-bar'),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: LayoutBuilder(builder: (context, box) {
                // Two keys a row on a phone, four on a wider panel.
                final columns = box.maxWidth >= 400 ? 4 : 2;
                const gap = 6.0;
                final width = ((box.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in tags)
                      SizedBox(
                        width: width,
                        child: _TagKey(tag: t, stacked: columns > 2, onPressed: () => bar.pick(t.id)),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tag as a hardware key with a glowing colour bar: beside the name ([stacked] false) or above it.
class _TagKey extends StatelessWidget {
  const _TagKey({required this.tag, required this.stacked, required this.onPressed});

  final ViewerTag tag;
  final bool stacked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      tag.label(AppLocalizations.of(context)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: stacked ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: stacked ? 15 : 17, fontWeight: FontWeight.w700),
    );
    return IrKey(
      key: ValueKey('tag-${tag.id}'),
      onPressed: onPressed,
      minHeight: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      // Fills the key: IrKey lays its child out from the top-left corner.
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: stacked
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ColourBar(colour: tag.colour, width: 26, height: 5),
                const SizedBox(height: 6),
                label,
              ])
            : Row(children: [
                _ColourBar(colour: tag.colour, width: 6, height: 26),
                const SizedBox(width: 10),
                Expanded(child: label),
              ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import 'tags.dart';

/// Edit the tag set (UX §3.5): add, rename, recolour, delete, drag to reorder. No limit on count.
/// With an Android library session it edits the session's template.
class TagEditorPage extends ConsumerWidget {
  const TagEditorPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const TagEditorPage());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.viewerTagsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('tag-add'),
        onPressed: () async {
          final count = ref.read(tagsProvider).length;
          final r = await showTagDialog(context, color: tagPalette[count % tagPalette.length]);
          if (r != null) ref.read(tagsProvider.notifier).add(r.name, r.color);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.viewerTagsAdd),
      ),
      body: const SafeArea(child: _TagList()),
    );
  }
}

class _TagList extends ConsumerWidget {
  const _TagList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tags = ref.watch(tagsProvider);
    final notifier = ref.read(tagsProvider.notifier);
    if (tags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.viewerTagsEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: tags.length,
          onReorderItem: notifier.reorder,
          itemBuilder: (context, i) {
            final t = tags[i];
            return Padding(
              key: ValueKey(t.id),
              padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
              child: IrPanel(
                padding: EdgeInsets.zero,
                child: _tagRow(context, l10n, notifier, t, i),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tagRow(BuildContext context, AppLocalizations l10n, TagsNotifier notifier, ViewerTag t, int i) => ListTile(
              minTileHeight: 60,
              leading: TagSwatch(color: t.color),
              title: Text(t.label(l10n), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              onTap: () async {
                final r = await showTagDialog(context, name: t.label(l10n), color: t.color);
                // An untouched default keeps following the app language.
                if (r != null) {
                  notifier.update(t.id, name: r.name == t.label(l10n) ? null : r.name, color: r.color);
                }
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.viewerTagDelete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      notifier.remove(t.id);
                      // Next to the drag handle, a slip is easy: offer an undo.
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(l10n.viewerTagDeleted(t.label(l10n))),
                          action: SnackBarAction(
                            label: l10n.viewerTagUndo,
                            onPressed: () => notifier.restore(t, i),
                          ),
                        ));
                    },
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle)),
                  ),
                ],
              ),
            );
}

/// One colour of the palette: a bordered square cell with the colour; the selected one has an
/// amber border, an amber-tinted fill and a check.
class _ColourChoice extends StatelessWidget {
  const _ColourChoice({required this.color, required this.selected, required this.onTap});

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final colour = Color(color);
    final onColour = ThemeData.estimateBrightnessForColor(colour) == Brightness.dark ? Colors.white : Colors.black;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        key: ValueKey('tag-color-$color'),
        color: selected ? c.signalSoft : c.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: selected ? c.signal : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
                child: selected ? Icon(Icons.check, size: 20, color: onColour) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tag's colour as a small square swatch.
class TagSwatch extends StatelessWidget {
  const TagSwatch({super.key, required this.color, this.size = 22});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: Color(color).withValues(alpha: 0.5), blurRadius: 6)],
        ),
      );
}

/// Name and colour of a new or edited tag; null when cancelled.
Future<({String name, int color})?> showTagDialog(BuildContext context, {String name = '', required int color}) =>
    showDialog<({String name, int color})>(
      context: context,
      builder: (_) => _TagDialog(name: name, color: color),
    );

class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.name, required this.color});

  final String name;
  final int color;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final _name = TextEditingController(text: widget.name);
  late int _color = widget.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) return;
    Navigator.of(context).pop((name: _name.text.trim(), color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.name.isEmpty ? l10n.viewerTagsAdd : l10n.viewerTagEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('tag-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.viewerTagName),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text(l10n.viewerTagColor, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in tagPalette) _ColourChoice(color: c, selected: c == _color, onTap: () => setState(() => _color = c)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.viewerTagCancel)),
        FilledButton(
          key: const ValueKey('tag-ok'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: Text(l10n.viewerTagOk),
        ),
      ],
    );
  }
}

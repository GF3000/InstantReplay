import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'tags.dart';

/// Edit the tag set (UX §3.5): add, rename, recolour, delete, drag to reorder. No limit on count.
class TagEditorPage extends ConsumerWidget {
  const TagEditorPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const TagEditorPage());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tags = ref.watch(tagsProvider);
    final notifier = ref.read(tagsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.viewerTagsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('tag-add'),
        onPressed: () async {
          final r = await showTagDialog(context, color: tagPalette[tags.length % tagPalette.length]);
          if (r != null) notifier.add(r.name, r.color);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.viewerTagsAdd),
      ),
      body: SafeArea(
        child: tags.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.viewerTagsEmpty, textAlign: TextAlign.center),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: tags.length,
                    onReorderItem: notifier.reorder,
                    itemBuilder: (context, i) {
                      final t = tags[i];
                      return ListTile(
                        key: ValueKey(t.id),
                        minTileHeight: 64,
                        leading: Icon(Icons.circle, color: t.colour, size: 28),
                        title: Text(t.label(l10n), style: const TextStyle(fontSize: 18)),
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
                              onPressed: () => notifier.remove(t.id),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
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
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in tagPalette)
                  IconButton(
                    key: ValueKey('tag-color-$c'),
                    iconSize: 32,
                    onPressed: () => setState(() => _color = c),
                    icon: Icon(c == _color ? Icons.check_circle : Icons.circle, color: Color(c)),
                  ),
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

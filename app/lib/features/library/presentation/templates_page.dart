import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/library_database.dart';
import '../data/templates.dart';
import '../labels.dart';
import '../library_providers.dart';

/// Tag templates (D18): the built-in ones and any imported. Export copies the JSON to the
/// clipboard; import takes pasted JSON. Labels are edited from the live screen's tag editor, on
/// the active session's template.
class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const TemplatesPage());

  Future<void> _export(BuildContext context, WidgetRef ref, TemplateRow t) async {
    final l10n = AppLocalizations.of(context);
    final spec = await ref.read(libraryDatabaseProvider).exportTemplate(t.id);
    if (spec == null) return;
    await Clipboard.setData(ClipboardData(text: resolveTemplateNames(l10n, spec).encode()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.libraryTemplateExported)));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final pasted = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    final spec = await showDialog<TemplateSpec>(
      context: context,
      builder: (_) => _ImportDialog(initial: pasted.trimLeft().startsWith('{') ? pasted : ''),
    );
    if (spec == null) return;
    await ref.read(libraryDatabaseProvider).importTemplate(spec);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.libraryTemplateImported(spec.name!))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final templates = ref.watch(libraryTemplatesProvider).value ?? const <TemplateRow>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTemplatesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('template-import'),
        onPressed: () => _import(context, ref),
        icon: const Icon(Icons.file_download_outlined),
        label: Text(l10n.libraryTemplateImport),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: templates.length,
          itemBuilder: (context, i) {
            final t = templates[i];
            return ListTile(
              key: ValueKey('template-${t.id}'),
              minTileHeight: 64,
              title: Text(templateLabel(l10n, t)),
              subtitle: t.builtIn ? Text(l10n.libraryTemplateBuiltIn) : null,
              trailing: PopupMenuButton<bool>(
                onSelected: (delete) async {
                  if (!delete) return _export(context, ref, t);
                  await ref.read(libraryDatabaseProvider).deleteTemplate(t.id);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: false,
                    child: ListTile(leading: const Icon(Icons.copy), title: Text(l10n.libraryTemplateExport)),
                  ),
                  if (!t.builtIn)
                    PopupMenuItem(
                      value: true,
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.libraryTemplateDelete),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.initial});

  final String initial;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      Navigator.of(context).pop(TemplateSpec.decode(_text.text));
    } on FormatException catch (e) {
      setState(() => _error = AppLocalizations.of(context).libraryTemplateImportError(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.libraryTemplateImport),
      content: SizedBox(
        width: 480,
        child: TextField(
          key: const ValueKey('template-json'),
          controller: _text,
          maxLines: 10,
          minLines: 5,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: l10n.libraryTemplateImportHint,
            errorText: _error,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.viewerTagCancel)),
        FilledButton(
          key: const ValueKey('template-import-ok'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: _submit,
          child: Text(l10n.libraryTemplateImport),
        ),
      ],
    );
  }
}

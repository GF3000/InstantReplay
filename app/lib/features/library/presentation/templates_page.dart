import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ir_colors.dart';
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
    final builtIn = [for (final t in templates) if (t.builtIn) t];
    final imported = [for (final t in templates) if (!t.builtIn) t];
    Widget section(String title, List<TemplateRow> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
              child: Text(
                title.toUpperCase(),
                style: irMono(12, weight: FontWeight.w600, color: context.ir.muted),
              ),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: context.ir.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, t) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _TemplateRow(
                    key: ValueKey('template-${t.id}'),
                    template: t,
                    onExport: () => _export(context, ref, t),
                    onDelete: t.builtIn ? null : () => ref.read(libraryDatabaseProvider).deleteTemplate(t.id),
                  ),
                ],
              ]),
            ),
          ],
        );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTemplatesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('template-import'),
        onPressed: () => _import(context, ref),
        icon: const Icon(Icons.file_download_outlined),
        label: Text(l10n.libraryTemplateImport),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 96),
              children: [
                if (builtIn.isNotEmpty) section(l10n.libTemplatesBuiltIn, builtIn),
                if (imported.isNotEmpty) section(l10n.libTemplatesImported, imported),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A template: its name, then copy as JSON and (imported ones) delete.
class _TemplateRow extends StatelessWidget {
  const _TemplateRow({super.key, required this.template, required this.onExport, required this.onDelete});

  final TemplateRow template;
  final VoidCallback onExport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    return ColoredBox(
      color: c.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(children: [
            Icon(template.builtIn ? Icons.sell_outlined : Icons.sell, color: c.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                templateLabel(l10n, template),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
              ),
            ),
            IconButton(
              key: ValueKey('template-export-${template.id}'),
              tooltip: l10n.libraryTemplateExport,
              icon: const Icon(Icons.copy),
              onPressed: onExport,
            ),
            if (onDelete != null)
              IconButton(
                key: ValueKey('template-delete-${template.id}'),
                tooltip: l10n.libraryTemplateDelete,
                color: c.liveText,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
          ]),
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
          style: irMono(13, weight: FontWeight.w500),
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

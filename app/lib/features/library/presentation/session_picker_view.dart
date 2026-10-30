import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../data/library_database.dart';
import '../data/templates.dart';
import '../labels.dart';
import '../library_providers.dart';
import 'library_page.dart';

/// Session picker (SPEC §5.1.3), between pairing and the live screen on Android: continue the
/// latest session or start a new one with a name, a type and a tag template.
class SessionPickerView extends ConsumerStatefulWidget {
  const SessionPickerView({super.key});

  @override
  ConsumerState<SessionPickerView> createState() => _SessionPickerViewState();
}

class _SessionPickerViewState extends ConsumerState<SessionPickerView> {
  final _name = TextEditingController();
  SessionType _type = SessionType.match;

  /// Null until the user picks one: then the default follows the latest session.
  String? _templateId;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The latest session's template, else the migrated tag set, else Generic.
  static String? _defaultTemplate(List<TemplateRow> templates, SessionRow? latest) {
    bool has(String? id) => id != null && templates.any((t) => t.id == id);
    if (has(latest?.templateId)) return latest!.templateId;
    if (has(BuiltInTemplates.migrated)) return BuiltInTemplates.migrated;
    if (has(BuiltInTemplates.generic)) return BuiltInTemplates.generic;
    return templates.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sessions = ref.watch(librarySessionsProvider);
    final templates = ref.watch(libraryTemplatesProvider).value ?? const <TemplateRow>[];
    final latest = sessions.value?.firstOrNull;
    final templateId = _templateId ?? _defaultTemplate(templates, latest?.session);
    final defaultName = l10n.librarySessionDefaultName(
      sessionTypeLabel(l10n, _type),
      DateFormat.MMMd(l10n.localeName).format(DateTime.now()),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (latest != null) ...[
              Text(l10n.librarySessionLatest, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  minTileHeight: 72,
                  title: Text(latest.session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(sessionSubtitle(l10n, latest)),
                  trailing: FilledButton(
                    key: const ValueKey('session-continue'),
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                    onPressed: _busy ? null : () => _run(() => ref.read(activeSessionProvider.notifier).resume(latest.session)),
                    child: Text(l10n.librarySessionContinue),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(l10n.librarySessionNew, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('session-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.librarySessionName,
                hintText: defaultName,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<SessionType>(
              segments: [
                for (final t in SessionType.values)
                  ButtonSegment(value: t, label: Text(sessionTypeLabel(l10n, t), overflow: TextOverflow.ellipsis)),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('session-template-$templateId'),
              initialValue: templateId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.librarySessionTemplate),
              items: [
                for (final t in templates)
                  DropdownMenuItem(value: t.id, child: Text(templateLabel(l10n, t), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) => setState(() => _templateId = id),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const ValueKey('session-start'),
                onPressed: _busy || templates.isEmpty
                    ? null
                    : () => _run(() => ref.read(activeSessionProvider.notifier).start(
                          name: _name.text.trim().isEmpty ? defaultName : _name.text.trim(),
                          type: _type,
                          templateId: templateId,
                        )),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.librarySessionStart, style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(LibraryPage.route()),
                icon: const Icon(Icons.video_library_outlined),
                label: Text(l10n.libraryTitle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Match · 30 Oct · 12 clips"
String sessionSubtitle(AppLocalizations l10n, SessionSummary s) => [
      sessionTypeLabel(l10n, s.session.type),
      DateFormat.MMMd(l10n.localeName).add_Hm().format(s.session.startedAt),
      l10n.librarySessionClips(s.clipCount),
    ].join(' · ');

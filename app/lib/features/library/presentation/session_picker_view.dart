import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../viewer/ui/connect_view.dart';
import '../../viewer/viewer_providers.dart';
import '../data/library_database.dart';
import '../data/templates.dart';
import '../labels.dart';
import '../library_providers.dart';
import 'library_page.dart';

/// Session picker (SPEC §5.1.3), the last step between pairing and the live screen on Android:
/// continue the latest session or start a new match or training, with an optional name and a tag
/// template.
class SessionPickerView extends ConsumerStatefulWidget {
  const SessionPickerView({super.key});

  @override
  ConsumerState<SessionPickerView> createState() => _SessionPickerViewState();
}

class _SessionPickerViewState extends ConsumerState<SessionPickerView> {
  final _name = TextEditingController();

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
    final c = context.ir;
    final sessions = ref.watch(librarySessionsProvider);
    final templates = ref.watch(libraryTemplatesProvider).value ?? const <TemplateRow>[];
    final latest = sessions.value?.firstOrNull;
    final templateId = _templateId ?? _defaultTemplate(templates, latest?.session);
    final cameraName = ref.watch(linkStateProvider.select((s) => s?.camera?.name));
    final canStart = !_busy && templates.isNotEmpty;

    void start(SessionType type) {
      final typed = _name.text.trim();
      final name = typed.isNotEmpty
          ? typed
          : l10n.librarySessionDefaultName(
              sessionTypeLabel(l10n, type),
              DateFormat.MMMd(l10n.localeName).format(DateTime.now()),
            );
      _run(() => ref.read(activeSessionProvider.notifier).start(name: name, type: type, templateId: templateId));
    }

    Widget newKey(Key key, SessionType type, IconData icon, String label, {bool lit = false}) => IrKey(
          key: key,
          led: lit ? c.signal : null,
          minHeight: 64,
          onPressed: canStart ? () => start(type) : null,
          // IrKey top-aligns its child: fill its height (less the LED strip) to centre the label.
          child: SizedBox(
            height: lit ? 56 : 64,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: c.signal),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
                ),
              ),
            ]),
          ),
        );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            const ConnectSteps(step: 2),
            const SizedBox(height: 22),
            if (cameraName != null) ...[
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle),
                  child: Icon(Icons.check, color: c.bg, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.connectPickerConnectedTo(cameraName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 24, height: 1.1, fontWeight: FontWeight.w700, color: c.text),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
            ],
            Text(l10n.connectPickerQuestion, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.muted)),
            const SizedBox(height: 12),
            if (latest != null) ...[
              IrPanel(
                key: const ValueKey('session-latest'),
                borderColor: c.signal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${l10n.librarySessionLatest} · '
                            '${DateFormat.MMMd(l10n.localeName).add_Hm().format(latest.session.startedAt)}'
                        .toUpperCase(),
                    style: irMono(12, weight: FontWeight.w600, color: c.signal),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latest.session.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text),
                  ),
                  Text(
                    [sessionTypeLabel(l10n, latest.session.type), l10n.librarySessionClips(latest.clipCount)].join(' · '),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.muted),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 60,
                child: FilledButton(
                  key: const ValueKey('session-continue'),
                  onPressed: _busy ? null : () => _run(() => ref.read(activeSessionProvider.notifier).resume(latest.session)),
                  child: Text(l10n.connectPickerContinue, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 22),
            ],
            _Label(l10n.librarySessionNew),
            const SizedBox(height: 8),
            IrPanel(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  key: const ValueKey('session-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.librarySessionName,
                    hintText: l10n.connectPickerNameHint,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
                const SizedBox(height: 14),
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
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: newKey(
                  const ValueKey('session-start'),
                  SessionType.match,
                  Icons.sports,
                  l10n.connectPickerNewMatch,
                  lit: latest == null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: newKey(
                  const ValueKey('session-start-training'),
                  SessionType.training,
                  Icons.fitness_center,
                  l10n.connectPickerNewTraining,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                key: const ValueKey('session-start-other'),
                style: TextButton.styleFrom(foregroundColor: c.muted),
                onPressed: canStart ? () => start(SessionType.other) : null,
                icon: const Icon(Icons.add, size: 20),
                label: Text(l10n.connectPickerNewOther),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: c.text),
                onPressed: () => Navigator.of(context).push(LibraryPage.route()),
                icon: const Icon(Icons.video_library_outlined, size: 20),
                label: Text(l10n.libraryTitle),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: irMono(12, weight: FontWeight.w600, color: context.ir.muted),
      );
}

/// "Match · 30 Oct 17:05 · 12 clips"
String sessionSubtitle(AppLocalizations l10n, SessionSummary s) => [
      sessionTypeLabel(l10n, s.session.type),
      DateFormat.MMMd(l10n.localeName).add_Hm().format(s.session.startedAt),
      l10n.librarySessionClips(s.clipCount),
    ].join(' · ');

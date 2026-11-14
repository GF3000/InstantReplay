import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/settings_providers.dart';
import '../clips/save_presets.dart';

/// How the Save buttons of this screen behave (SPEC §5.1.7): default duration, quick choices
/// and post-roll. Lives in the Viewer's menu, next to the panel switches: it is about this
/// screen, not the app. Narrow (a phone): the default duration is a drop-down.
class SaveButtonSettings extends ConsumerWidget {
  const SaveButtonSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final presets = ref.watch(savePresetsProvider);
    final notifier = ref.read(savePresetsProvider.notifier);
    Widget title(String text, {String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            if (hint != null) Text(hint, style: TextStyle(fontSize: 13, color: c.muted)),
          ]),
        );
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 480;
      final defaultChoice = narrow
          ? Row(children: [
              Expanded(
                child: Text(l10n.settingsDefaultDuration,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
              ),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.lineStrong),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    key: const ValueKey('settings-default'),
                    value: presets.defaultSeconds,
                    style: irMono(16, weight: FontWeight.w600, color: c.text),
                    dropdownColor: c.surface,
                    items: [
                      for (final s in SavePresets.durationOptions)
                        DropdownMenuItem(value: s, child: Text(l10n.viewerSaveQuick(s))),
                    ],
                    onChanged: (s) => s == null ? null : notifier.setDefault(s),
                  ),
                ),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title(l10n.settingsDefaultDuration),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in SavePresets.durationOptions)
                  DurationChoice(
                    key: ValueKey('settings-default-$s'),
                    label: l10n.viewerSaveQuick(s),
                    selected: presets.defaultSeconds == s,
                    onTap: () => notifier.setDefault(s),
                  ),
              ]),
            ]);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          defaultChoice,
          const SizedBox(height: 16),
          title(l10n.settingsQuickPresets, hint: l10n.settingsQuickPresetsHint(SavePresets.maxQuick)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in SavePresets.durationOptions)
              if (presets.quickSeconds.contains(s) case final selected)
                DurationChoice(
                  key: ValueKey('settings-quick-$s'),
                  label: l10n.viewerSaveQuick(s),
                  selected: selected,
                  check: true,
                  compact: narrow,
                  // Keep 1 to maxQuick chips: the last one can't be removed, a 4th can't be added.
                  onTap: (selected
                          ? presets.quickSeconds.length > 1
                          : presets.quickSeconds.length < SavePresets.maxQuick)
                      ? () => notifier.toggleQuick(s)
                      : null,
                ),
          ]),
          const SizedBox(height: 16),
          title(l10n.settingsPostRoll(presets.postSeconds), hint: l10n.settingsPostRollHint),
          Row(children: [
            Expanded(
              child: Slider(
                key: const ValueKey('settings-post'),
                value: presets.postSeconds.toDouble(),
                max: SavePresets.maxPostSeconds.toDouble(),
                divisions: SavePresets.maxPostSeconds,
                label: l10n.viewerSaveQuick(presets.postSeconds),
                onChanged: (v) => notifier.setPost(v.round()),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(l10n.viewerSaveQuick(presets.postSeconds),
                  textAlign: TextAlign.end, style: irMono(16, color: c.text)),
            ),
          ]),
        ]),
      );
    });
  }
}

/// A duration chip: mono label, amber border and fill when selected; [check] adds a tick for
/// multiple choice.
class DurationChoice extends StatelessWidget {
  const DurationChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.check = false,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool check;

  /// Narrower chips so the seven durations fit two rows on a phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Semantics(
      selected: selected,
      button: true,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          color: selected ? c.signalSoft : c.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: selected ? c.signal : c.line),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 48, minWidth: compact ? 48 : 60),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (check && selected) ...[Icon(Icons.check, size: 16, color: c.signal), const SizedBox(width: 4)],
                  Text(label, style: irMono(15, weight: FontWeight.w600, color: c.text)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../library/library_providers.dart';
import '../viewer/clips/save_presets.dart';
import 'settings_providers.dart';

/// Viewer settings (SPEC §5.1.7, v0.1 subset): Save button durations, post-roll, language, theme
/// and storage used by saved clips.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// Language names are shown in their own language, whatever the current one is.
  static const _languageNames = {'es': 'Español', 'en': 'English'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final presets = ref.watch(savePresetsProvider);
    final presetsNotifier = ref.read(savePresetsProvider.notifier);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final showStorage = ref.watch(libraryEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
              _Header(l10n.settingsSaveSection),
              _Section(children: [
                _Field(
                  title: l10n.settingsDefaultDuration,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in SavePresets.durationOptions)
                      _Choice(
                        key: ValueKey('settings-default-$s'),
                        label: l10n.viewerSaveQuick(s),
                        selected: presets.defaultSeconds == s,
                        onTap: () => presetsNotifier.setDefault(s),
                      ),
                  ]),
                ),
                _Field(
                  title: l10n.settingsQuickPresets,
                  subtitle: l10n.settingsQuickPresetsHint(SavePresets.maxQuick),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in SavePresets.durationOptions)
                      if (presets.quickSeconds.contains(s) case final selected)
                        _Choice(
                          key: ValueKey('settings-quick-$s'),
                          label: l10n.viewerSaveQuick(s),
                          selected: selected,
                          check: true,
                          // Keep 1 to maxQuick chips: the last one can't be removed, a 4th can't be added.
                          onTap: (selected
                                  ? presets.quickSeconds.length > 1
                                  : presets.quickSeconds.length < SavePresets.maxQuick)
                              ? () => presetsNotifier.toggleQuick(s)
                              : null,
                        ),
                  ]),
                ),
                _Field(
                  title: l10n.settingsPostRoll(presets.postSeconds),
                  subtitle: l10n.settingsPostRollHint,
                  child: Row(children: [
                    Expanded(
                      child: Slider(
                        key: const ValueKey('settings-post'),
                        value: presets.postSeconds.toDouble(),
                        max: SavePresets.maxPostSeconds.toDouble(),
                        divisions: SavePresets.maxPostSeconds,
                        label: l10n.viewerSaveQuick(presets.postSeconds),
                        onChanged: (v) => presetsNotifier.setPost(v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        l10n.viewerSaveQuick(presets.postSeconds),
                        textAlign: TextAlign.end,
                        style: irMono(16, color: context.ir.text),
                      ),
                    ),
                  ]),
                ),
              ]),
              _Header(l10n.settingsDisplaySection),
              _Section(children: [
                _Field(
                  title: l10n.settingsLanguage,
                  child: IrSegmented<String>(
                    key: const ValueKey('settings-language'),
                    values: ['', ..._languageNames.keys],
                    labelOf: (code) => code.isEmpty ? l10n.settingsSystem : _languageNames[code]!,
                    selected: locale?.languageCode ?? '',
                    onChanged: (code) => ref.read(localeProvider.notifier).set(code.isEmpty ? null : Locale(code)),
                  ),
                ),
                _Field(
                  title: l10n.settingsTheme,
                  child: IrSegmented<ThemeMode>(
                    key: const ValueKey('settings-theme'),
                    values: const [ThemeMode.dark, ThemeMode.light, ThemeMode.system],
                    labelOf: (mode) => switch (mode) {
                      ThemeMode.dark => l10n.settingsThemeDark,
                      ThemeMode.light => l10n.settingsThemeLight,
                      ThemeMode.system => l10n.settingsSystem,
                    },
                    selected: themeMode,
                    onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode),
                  ),
                ),
              ]),
              if (showStorage) ...[
                _Header(l10n.settingsStorageSection),
                const _Section(children: [_StorageTile()]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A section title: small, upper case, muted.
class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
        child: Text(text.toUpperCase(), style: irMono(12, weight: FontWeight.w600, color: context.ir.muted)),
      );
}

/// The settings of a section in one bordered panel, divided by hairlines.
class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IrPanel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const Divider(height: 1),
            child,
          ],
        ]),
      );
}

/// A setting: its title, an optional hint and the control below.
class _Field extends StatelessWidget {
  const _Field({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
        if (subtitle case final subtitle?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle, style: TextStyle(fontSize: 13, color: c.muted)),
          ),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

/// A duration chip: mono label, amber border and fill when selected; [check] adds a tick for
/// multiple choice.
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap, this.check = false});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool check;

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
              constraints: const BoxConstraints(minHeight: 48, minWidth: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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

class _StorageTile extends ConsumerWidget {
  const _StorageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final usage = ref.watch(storageUsageProvider);
    final localeName = Localizations.localeOf(context).toLanguageTag();
    return Padding(
      key: const ValueKey('settings-storage'),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(Icons.sd_storage_outlined, color: c.muted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.settingsStorageClips, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
            Text(
              switch (usage) {
                AsyncData(value: final u?) => l10n.settingsStorageUsage(formatBytes(u.bytes, localeName), u.clips),
                AsyncError() || AsyncData() => l10n.settingsStorageUnavailable,
                _ => '…',
              },
              style: irMono(14, weight: FontWeight.w500, color: c.muted),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// `850 KB`, `12.3 MB`, `1.4 GB` with the locale's decimal separator.
String formatBytes(int bytes, String locale) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final number = NumberFormat.decimalPattern(locale)..maximumFractionDigits = unit < 2 ? 0 : 1;
  return '${number.format(value)} ${units[unit]}';
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/capabilities.dart';
import '../../l10n/app_localizations.dart';
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
    final showStorage = ref.watch(capabilitiesProvider.select((c) => c.hasPersistentLibrary));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              _Header(l10n.settingsSaveSection),
              _Field(
                title: l10n.settingsDefaultDuration,
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in SavePresets.durationOptions)
                    ChoiceChip(
                      key: ValueKey('settings-default-$s'),
                      label: Text(l10n.viewerSaveQuick(s)),
                      selected: presets.defaultSeconds == s,
                      onSelected: (_) => presetsNotifier.setDefault(s),
                    ),
                ]),
              ),
              _Field(
                title: l10n.settingsQuickPresets,
                subtitle: l10n.settingsQuickPresetsHint(SavePresets.maxQuick),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in SavePresets.durationOptions)
                    if (presets.quickSeconds.contains(s) case final selected)
                      FilterChip(
                        key: ValueKey('settings-quick-$s'),
                        label: Text(l10n.viewerSaveQuick(s)),
                        selected: selected,
                        // Keep 1 to maxQuick chips: the last one can't be removed, a 4th can't be added.
                        onSelected: (selected
                                ? presets.quickSeconds.length > 1
                                : presets.quickSeconds.length < SavePresets.maxQuick)
                            ? (_) => presetsNotifier.toggleQuick(s)
                            : null,
                      ),
                ]),
              ),
              _Field(
                title: l10n.settingsPostRoll(presets.postSeconds),
                subtitle: l10n.settingsPostRollHint,
                child: Slider(
                  key: const ValueKey('settings-post'),
                  value: presets.postSeconds.toDouble(),
                  max: SavePresets.maxPostSeconds.toDouble(),
                  divisions: SavePresets.maxPostSeconds,
                  label: l10n.viewerSaveQuick(presets.postSeconds),
                  onChanged: (v) => presetsNotifier.setPost(v.round()),
                ),
              ),
              const Divider(),
              _Header(l10n.settingsDisplaySection),
              _Field(
                title: l10n.settingsLanguage,
                child: SegmentedButton<String>(
                  key: const ValueKey('settings-language'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: '', label: Text(l10n.settingsSystem)),
                    for (final MapEntry(:key, :value) in _languageNames.entries)
                      ButtonSegment(value: key, label: Text(value)),
                  ],
                  selected: {locale?.languageCode ?? ''},
                  onSelectionChanged: (s) =>
                      ref.read(localeProvider.notifier).set(s.single.isEmpty ? null : Locale(s.single)),
                ),
              ),
              _Field(
                title: l10n.settingsTheme,
                child: SegmentedButton<ThemeMode>(
                  key: const ValueKey('settings-theme'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_outlined),
                      label: Text(l10n.settingsThemeDark),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_outlined),
                      label: Text(l10n.settingsThemeLight),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.brightness_auto_outlined),
                      label: Text(l10n.settingsSystem),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.single),
                ),
              ),
              if (showStorage) ...[
                const Divider(),
                _Header(l10n.settingsStorageSection),
                const _StorageTile(),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// A setting: its title, an optional hint and the control below.
class _Field extends StatelessWidget {
  const _Field({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle case final subtitle?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        child,
      ]),
    );
  }
}

class _StorageTile extends ConsumerWidget {
  const _StorageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final usage = ref.watch(storageUsageProvider);
    final localeName = Localizations.localeOf(context).toLanguageTag();
    return ListTile(
      key: const ValueKey('settings-storage'),
      leading: const Icon(Icons.sd_storage_outlined),
      title: Text(l10n.settingsStorageClips),
      subtitle: Text(switch (usage) {
        AsyncData(value: final u?) => l10n.settingsStorageUsage(formatBytes(u.bytes, localeName), u.clips),
        AsyncError() || AsyncData() => l10n.settingsStorageUnavailable,
        _ => '…',
      }),
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

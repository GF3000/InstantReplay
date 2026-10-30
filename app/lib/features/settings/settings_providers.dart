import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import '../library/library_providers.dart';
import '../viewer/clips/save_presets.dart';
import 'storage_usage.dart';

/// Writes a setting without failing the UI: on web this is localStorage, which can be full or
/// unavailable (private mode), and the in-memory value still applies for this session.
void _persist(Future<bool> write) => unawaited(write.catchError((Object e) {
      debugPrint('Could not save a setting: $e');
      return false;
    }));

/// Save button durations and post-roll (D11), persisted in shared_preferences.
class SavePresetsNotifier extends Notifier<SavePresets> {
  static const defaultKey = 'viewer.save.default';
  static const quickKey = 'viewer.save.quick';
  static const postKey = 'viewer.save.post';

  @override
  SavePresets build() {
    const fallback = SavePresets();
    final prefs = ref.watch(sharedPreferencesProvider);
    final def = prefs.getInt(defaultKey);
    final quick = _validQuick(prefs.getStringList(quickKey)?.map(int.tryParse).nonNulls);
    final post = prefs.getInt(postKey);
    return SavePresets(
      defaultSeconds: SavePresets.durationOptions.contains(def) ? def! : fallback.defaultSeconds,
      quickSeconds: quick ?? fallback.quickSeconds,
      postSeconds: post != null && post >= 0 && post <= SavePresets.maxPostSeconds ? post : fallback.postSeconds,
    );
  }

  void setDefault(int seconds) {
    if (!SavePresets.durationOptions.contains(seconds)) return;
    state = state.copyWith(defaultSeconds: seconds);
    _persist(ref.read(sharedPreferencesProvider).setInt(defaultKey, seconds));
  }

  /// Adds or removes a quick chip. At least one and at most [SavePresets.maxQuick] stay selected.
  void toggleQuick(int seconds) {
    final current = state.quickSeconds;
    final next = _validQuick(current.contains(seconds) ? current.where((s) => s != seconds) : [...current, seconds]);
    if (next == null) return;
    state = state.copyWith(quickSeconds: next);
    _persist(ref.read(sharedPreferencesProvider).setStringList(quickKey, [for (final s in next) '$s']));
  }

  void setPost(int seconds) {
    if (seconds < 0 || seconds > SavePresets.maxPostSeconds) return;
    state = state.copyWith(postSeconds: seconds);
    _persist(ref.read(sharedPreferencesProvider).setInt(postKey, seconds));
  }

  /// Sorted and deduplicated, or null when empty, too long or holding an unknown duration.
  static List<int>? _validQuick(Iterable<int>? values) {
    if (values == null) return null;
    final list = values.toSet().toList()..sort();
    if (list.isEmpty || list.length > SavePresets.maxQuick) return null;
    return list.every(SavePresets.durationOptions.contains) ? List.unmodifiable(list) : null;
  }
}

final savePresetsProvider = NotifierProvider<SavePresetsNotifier, SavePresets>(SavePresetsNotifier.new);

/// Dark by default (D20); light and system are available in Settings.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const storageKey = 'app.theme';

  @override
  ThemeMode build() =>
      ThemeMode.values.asNameMap()[ref.watch(sharedPreferencesProvider).getString(storageKey)] ?? ThemeMode.dark;

  void set(ThemeMode mode) {
    state = mode;
    _persist(ref.read(sharedPreferencesProvider).setString(storageKey, mode.name));
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// The app language: null follows the system (falling back to English), else `es` or `en`.
class LocaleNotifier extends Notifier<Locale?> {
  static const storageKey = 'app.locale';
  static const supported = ['es', 'en'];

  @override
  Locale? build() {
    final code = ref.watch(sharedPreferencesProvider).getString(storageKey);
    return supported.contains(code) ? Locale(code!) : null;
  }

  void set(Locale? locale) {
    final code = locale?.languageCode;
    if (code != null && !supported.contains(code)) return;
    state = code == null ? null : Locale(code);
    final prefs = ref.read(sharedPreferencesProvider);
    _persist(code == null ? prefs.remove(storageKey) : prefs.setString(storageKey, code));
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

/// Space taken by the clips in the library; null without one (web keeps clips in memory, D15).
/// Read again each time the Settings screen opens.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage?>((ref) async {
  if (!ref.watch(libraryEnabledProvider)) return null;
  final (bytes, clips) = await ref.watch(libraryDatabaseProvider).usage();
  return StorageUsage(bytes: bytes, clips: clips);
});

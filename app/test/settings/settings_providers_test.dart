import 'dart:math' as math;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/theme.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/library/data/library_database.dart';
import 'package:instant_replay/features/library/library_providers.dart';
import 'package:instant_replay/features/settings/settings_page.dart';
import 'package:instant_replay/features/settings/settings_providers.dart';
import 'package:instant_replay/features/viewer/clips/save_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([Map<String, Object> saved = const {}]) async {
  SharedPreferences.setMockInitialValues(saved);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

/// A fresh container over the same preferences, like the next app start.
ProviderContainer _restart(ProviderContainer c) {
  final prefs = c.read(sharedPreferencesProvider);
  final next = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(next.dispose);
  return next;
}

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('save presets', () {
    test('defaults: 20 s, quick 10/30/60 s, post-roll 2 s', () async {
      final c = await _container();
      expect(c.read(savePresetsProvider), const SavePresets());
    });

    test('changes persist across restarts', () async {
      final c = await _container();
      final n = c.read(savePresetsProvider.notifier);
      n.setDefault(30);
      n.toggleQuick(60);
      n.toggleQuick(5);
      n.setPost(4);
      const expected = SavePresets(defaultSeconds: 30, quickSeconds: [5, 10, 30], postSeconds: 4);
      expect(c.read(savePresetsProvider), expected);
      await pumpEventQueue();
      expect(_restart(c).read(savePresetsProvider), expected);
      final r = expected.request(requestId: 'x', viewerId: 'me');
      expect((r.preSeconds, r.postSeconds), (30.0, 4.0));
    });

    test('quick chips stay between 1 and 3, sorted', () async {
      final c = await _container();
      final n = c.read(savePresetsProvider.notifier);
      n.toggleQuick(15);
      expect(c.read(savePresetsProvider).quickSeconds, [10, 30, 60], reason: 'a 4th is refused');
      n.toggleQuick(10);
      n.toggleQuick(30);
      expect(c.read(savePresetsProvider).quickSeconds, [60]);
      n.toggleQuick(60);
      expect(c.read(savePresetsProvider).quickSeconds, [60], reason: 'the last one stays');
      n.toggleQuick(5);
      expect(c.read(savePresetsProvider).quickSeconds, [5, 60]);
    });

    test('out-of-range values are refused', () async {
      final c = await _container();
      final n = c.read(savePresetsProvider.notifier);
      n.setDefault(90);
      n.setPost(6);
      n.setPost(-1);
      n.toggleQuick(7);
      expect(c.read(savePresetsProvider), const SavePresets());
    });

    test('corrupt stored values fall back to the defaults', () async {
      final c = await _container({
        SavePresetsNotifier.defaultKey: 120,
        SavePresetsNotifier.quickKey: ['10', '20', '30', '60'],
        SavePresetsNotifier.postKey: 9,
      });
      expect(c.read(savePresetsProvider), const SavePresets());
      final c2 = await _container({SavePresetsNotifier.quickKey: ['x', '60', '10', '10']});
      expect(c2.read(savePresetsProvider).quickSeconds, [10, 60]);
    });
  });

  group('theme', () {
    test('dark by default (D20), persisted when changed', () async {
      final c = await _container();
      expect(c.read(themeModeProvider), ThemeMode.dark);
      c.read(themeModeProvider.notifier).set(ThemeMode.light);
      expect(c.read(themeModeProvider), ThemeMode.light);
      await pumpEventQueue();
      expect(_restart(c).read(themeModeProvider), ThemeMode.light);
    });

    test('an unknown stored value means dark', () async {
      final c = await _container({ThemeModeNotifier.storageKey: 'sepia'});
      expect(c.read(themeModeProvider), ThemeMode.dark);
    });

    // N10: contrast ≥ 7:1 on the main screen, in both themes.
    for (final (name, theme) in [('dark', AppTheme.dark), ('light', AppTheme.light)]) {
      test('$name theme keeps 7:1 contrast for text and the Save button', () {
        final s = theme.colorScheme;
        expect(_contrast(s.onSurface, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(7));
        expect(_contrast(s.onSurfaceVariant, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(7));
        expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(7));
        expect(_contrast(s.primary, theme.scaffoldBackgroundColor), greaterThanOrEqualTo(7));
      });
    }
  });

  group('language', () {
    test('follows the system until one is chosen', () async {
      final c = await _container();
      expect(c.read(localeProvider), isNull);
      c.read(localeProvider.notifier).set(const Locale('es'));
      expect(c.read(localeProvider), const Locale('es'));
      await pumpEventQueue();
      expect(_restart(c).read(localeProvider), const Locale('es'));
      c.read(localeProvider.notifier).set(null);
      await pumpEventQueue();
      expect(_restart(c).read(localeProvider), isNull);
    });

    test('unsupported languages are ignored', () async {
      final c = await _container({LocaleNotifier.storageKey: 'fr'});
      expect(c.read(localeProvider), isNull);
      c.read(localeProvider.notifier).set(const Locale('de'));
      expect(c.read(localeProvider), isNull);
    });
  });

  group('storage usage', () {
    Future<ProviderContainer> withLibrary(Capabilities caps) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = LibraryDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final session = await db.createSession(name: 's', type: SessionType.match);
      for (final (id, size) in [('a', 1000), ('b', 2500)]) {
        await db.addClip(ClipsCompanion.insert(
          id: id,
          sessionId: session.id,
          requestId: Value(id),
          requestedAt: DateTime(2026, 10, 30),
          filePath: '/files/clips/${session.id}/$id.mp4',
          sizeBytes: size,
          createdAt: DateTime(2026, 10, 30),
          updatedAt: DateTime(2026, 10, 30),
        ));
      }
      final c = ProviderContainer(overrides: [
        libraryDatabaseProvider.overrideWithValue(db),
        capabilitiesProvider.overrideWithValue(caps),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('sums the clips in the library', () async {
      final c = await withLibrary(Capabilities.nativeAndroid);
      final usage = (await c.read(storageUsageProvider.future))!;
      expect((usage.bytes, usage.clips), (3500, 2));
    });

    test('is null without a library (web)', () async {
      final c = await withLibrary(Capabilities.web);
      expect(await c.read(storageUsageProvider.future), isNull);
    });
  });

  test('formatBytes', () {
    expect(formatBytes(0, 'en'), '0 B');
    expect(formatBytes(850000, 'en'), '850 KB');
    expect(formatBytes(12345678, 'en'), '12.3 MB');
    expect(formatBytes(12345678, 'es'), '12,3 MB');
    expect(formatBytes(1400000000, 'en'), '1.4 GB');
  });
}

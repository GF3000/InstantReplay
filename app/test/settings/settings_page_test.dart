import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/settings/settings_providers.dart';
import 'package:instant_replay/features/settings/storage_usage.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _pumpViewer(WidgetTester tester, {Capabilities caps = Capabilities.nativeAndroid}) async {
  SharedPreferences.setMockInitialValues({'role': 'viewer'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(caps),
      storageUsageProvider.overrideWith((_) async => const StorageUsage(bytes: 12345678, clips: 2)),
    ],
    child: const InstantReplayApp(),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('viewer-settings')));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.localesTestValue = const [Locale('en')]);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  testWidgets('opens from the Viewer and applies changes at once', (tester) async {
    final prefs = await _pumpViewer(tester);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-default-30')));
    await tester.pumpAndSettle();
    expect(prefs.getInt(SavePresetsNotifier.defaultKey), 30);

    await tester.scrollUntilVisible(find.byKey(const ValueKey('settings-theme')), 200);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Settings'))).brightness, Brightness.light);

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    expect(prefs.getString(LocaleNotifier.storageKey), 'es');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('settings-storage')), 200);
    expect(find.text('12,3 MB en 2 clips'), findsOneWidget);

    await tester.tap(find.byType(BackButton)); // pageBack() looks for the English tooltip
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsNothing);
  });

  testWidgets('web hides storage usage', (tester) async {
    await _pumpViewer(tester, caps: Capabilities.web);
    expect(find.text('Settings'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Theme'), 200);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-storage')), findsNothing);
  });

  test('changing presets keeps the session clips (the clips notifier is not rebuilt)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final sub = c.listen(viewerClipsProvider, (_, _) {});
    addTearDown(sub.close);
    final before = c.read(viewerClipsProvider.notifier);
    c.read(savePresetsProvider.notifier).setDefault(45);
    await pumpEventQueue();
    expect(identical(c.read(viewerClipsProvider.notifier), before), isTrue);
  });
}

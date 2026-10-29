import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _pumpApp(
  WidgetTester tester, {
  Capabilities caps = Capabilities.nativeAndroid,
  Map<String, Object> saved = const {},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(caps),
    ],
    child: const InstantReplayApp(),
  ));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.localesTestValue = const [Locale('en')]);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  testWidgets('role gate offers Camera and Viewer when the device can capture', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Choose a role'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Viewer'), findsOneWidget);
    expect(find.text('Lab (Phase 0 harness)'), findsOneWidget);
  });

  testWidgets('role gate offers only Viewer on web', (tester) async {
    await _pumpApp(tester, caps: Capabilities.web);
    expect(find.text('Camera'), findsNothing);
    expect(find.text('Viewer'), findsOneWidget);
    expect(find.text('Lab (Phase 0 harness)'), findsNothing);
  });

  testWidgets('renders Spanish strings under the es locale', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('es', 'ES')];
    await _pumpApp(tester);
    expect(find.text('Elige un rol'), findsOneWidget);
    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Visor'), findsOneWidget);
  });

  testWidgets('falls back to English for unsupported locales', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    await _pumpApp(tester);
    expect(find.text('Choose a role'), findsOneWidget);
  });

  testWidgets('choosing a role saves it and opens its screen', (tester) async {
    final prefs = await _pumpApp(tester);
    await tester.tap(find.text('Viewer'));
    await tester.pumpAndSettle();
    expect(find.text('The Viewer screen arrives in M4.'), findsOneWidget);
    expect(prefs.getString('role'), 'viewer');
  });

  testWidgets('a saved role redirects on launch and can be switched', (tester) async {
    final prefs = await _pumpApp(tester, saved: {'role': 'camera'});
    expect(find.text('The Camera screen arrives in M3.'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch role'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a role'), findsOneWidget);
    expect(prefs.getString('role'), isNull);
  });

  testWidgets('a saved Camera role is ignored where capture is unavailable', (tester) async {
    await _pumpApp(tester, caps: Capabilities.web, saved: {'role': 'camera'});
    expect(find.text('Choose a role'), findsOneWidget);
  });
}

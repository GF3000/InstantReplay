import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/core/ui/bucle_logo.dart';
import 'package:instant_replay/features/role/role.dart';
import 'package:instant_replay/features/role/role_gate_page.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> saved, {Capabilities caps = Capabilities.nativeAndroid}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    capabilitiesProvider.overrideWithValue(caps),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a Camera left in the old broadcast mode becomes the Broadcast role, once', () async {
    final c = await _container({'role': 'camera', 'camera.mode': 'broadcast'});
    expect(c.read(roleProvider), AppRole.broadcast);
    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString('role'), 'broadcast');
    expect(prefs.containsKey('camera.mode'), isFalse);
  });

  test('the old replay mode stays a Camera; a Viewer is untouched', () async {
    expect((await _container({'role': 'camera', 'camera.mode': 'replay'})).read(roleProvider), AppRole.camera);
    expect((await _container({'role': 'viewer', 'camera.mode': 'broadcast'})).read(roleProvider), AppRole.viewer);
  });

  test('a device that cannot capture forgets the Camera and Broadcast roles', () async {
    expect((await _container({'role': 'broadcast'}, caps: Capabilities.web)).read(roleProvider), isNull);
    expect(AppRole.broadcast.captures, isTrue);
    expect(AppRole.viewer.captures, isFalse);
  });

  testWidgets('the start screen offers Camera and Viewer, and Broadcast smaller below', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
      ],
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoleGatePage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Visor'), findsOneWidget);
    expect(find.text('Retransmitir partido · beta'), findsOneWidget);
    expect(find.byType(BucleLogo), findsOneWidget);
    expect(find.text('InstantReplay'), findsOneWidget);
    final camera = tester.getRect(find.byKey(const ValueKey('role-camera')));
    final broadcast = tester.getRect(find.byKey(const ValueKey('role-broadcast')));
    expect(broadcast.top, greaterThan(camera.bottom), reason: 'below the main two');
    expect(broadcast.height, lessThan(camera.height), reason: 'smaller than the main buttons');
  });

  testWidgets('landscape phone: Camera | Viewer side by side and Broadcast below, all on screen', (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
      ],
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoleGatePage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Rect button(String key) => tester.getRect(find.byKey(ValueKey(key)));
    final camera = button('role-camera'), viewer = button('role-viewer');
    final broadcast = tester.getRect(find.byKey(const ValueKey('role-broadcast')));
    expect(camera.top, viewer.top, reason: 'side by side');
    expect(viewer.left, greaterThan(camera.right));
    expect(broadcast.top, greaterThan(camera.bottom));
    expect(broadcast.bottom, lessThanOrEqualTo(1080 / 2.5), reason: 'visible without scrolling');
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(800, 416), Size(1280, 800)]) {
    testWidgets('no overflow at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RoleGatePage(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('role-broadcast')), findsOneWidget);
    });
  }
}

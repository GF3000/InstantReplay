import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/discovery/discovered_camera.dart';
import 'package:instant_replay/features/discovery/nsd.dart';
import 'package:instant_replay/features/viewer/scan/qr_scan_page.dart';
import 'package:instant_replay/features/viewer/scan/qr_scanner.dart';
import 'package:instant_replay/features/viewer/ui/connect_view.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoScanner implements QrScanner {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Widget preview({required ValueChanged<String> onCode}) => const SizedBox.shrink();
}

void main() {
  late ProviderContainer container;
  late StreamController<List<DiscoveredCamera>> found;
  var listening = false;

  Future<void> pump(WidgetTester tester, {Capabilities capabilities = Capabilities.nativeAndroid}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    found = StreamController<List<DiscoveredCamera>>(
      onListen: () => listening = true,
      onCancel: () => listening = false,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pageUriProvider.overrideWithValue(null),
        qrScannerProvider.overrideWithValue(_NoScanner()),
        capabilitiesProvider.overrideWithValue(capabilities),
        cameraBrowserProvider.overrideWithValue(() => found.stream),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          ref.watch(viewerSetupProvider);
          return const AddressForm();
        })),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const pixel = DiscoveredCamera(cameraId: 'abc', name: 'Google Pixel 7', host: '192.168.43.1', port: 8080);

  testWidgets('lists Cameras as they are found, above the address field', (tester) async {
    await pump(tester);
    expect(listening, isTrue);
    expect(find.text('Looking for cameras…'), findsOneWidget);

    found.add([pixel]);
    await tester.pumpAndSettle();
    expect(find.text('Looking for cameras…'), findsNothing);
    expect(find.text('Google Pixel 7'), findsOneWidget);
    expect(find.text('http://192.168.43.1:8080'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Google Pixel 7')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );

    found.add([]);
    await tester.pumpAndSettle();
    expect(find.text('Google Pixel 7'), findsNothing);
  });

  testWidgets('tapping a Camera goes on to its code', (tester) async {
    await pump(tester);
    found.add([pixel]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Google Pixel 7'));
    await tester.pumpAndSettle();
    final setup = container.read(viewerSetupProvider);
    expect(setup.base, Uri.parse('http://192.168.43.1:8080'));
    expect(setup.token, isNull);
  });

  testWidgets('a Camera on another protocol version cannot be picked', (tester) async {
    await pump(tester);
    found.add([const DiscoveredCamera(cameraId: 'x', name: 'Old phone', host: '10.0.0.2', port: 8080, version: 99)]);
    await tester.pumpAndSettle();
    expect(find.text('Different InstantReplay version'), findsOneWidget);

    await tester.tap(find.text('Old phone'));
    await tester.pumpAndSettle();
    expect(container.read(viewerSetupProvider).base, isNull);
  });

  testWidgets('no list or browsing where NSD is unavailable (web)', (tester) async {
    await pump(tester, capabilities: Capabilities.web);
    expect(listening, isFalse);
    expect(find.text('Cameras on this network'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('browsing stops when the form goes away', (tester) async {
    await pump(tester);
    expect(listening, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(listening, isFalse);
  });
}

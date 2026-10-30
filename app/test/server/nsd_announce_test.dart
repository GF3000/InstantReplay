import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/camera/capture_layer.dart';
import 'package:instant_replay/features/server/api_server.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera/fake_capture_layer.dart';
import '../camera/fake_server_platform.dart';

/// The address is polled every 5 s.
const _addressRefresh = Duration(seconds: 6);

Future<void> _pumpCamera(WidgetTester tester, FakeServerPlatform server) async {
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'role': 'camera', 'cameraId': 'cafe0001'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
      captureLayerProvider.overrideWithValue(FakeCaptureLayer()),
      serverPlatformProvider.overrideWithValue(server.platform),
    ],
    child: const InstantReplayApp(),
  ));
  await tester.pumpAndSettle();
}

Future<void> _closeCamera(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.localesTestValue = const [Locale('en')]);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  testWidgets('announces the running server with the SPEC TXT record', (tester) async {
    final server = FakeServerPlatform();
    await _pumpCamera(tester, server);

    expect(server.announcements, hasLength(1));
    final advert = server.announcements.single.advert;
    expect(advert.name, 'Test Phone');
    expect(advert.port, defaultPort);
    expect(advert.txt, {'v': '$protocolVersion', 'cameraId': 'cafe0001', 'name': 'Test Phone'});
    expect(server.announcements.single.stopped, isFalse);

    await _closeCamera(tester);
    expect(server.announcements.single.stopped, isTrue);
  });

  testWidgets('waits for a network, and re-announces when the address changes', (tester) async {
    final server = FakeServerPlatform(address: null);
    await _pumpCamera(tester, server);
    expect(server.announcements, isEmpty);

    server.address = '192.168.43.1';
    await tester.pump(_addressRefresh);
    await tester.pumpAndSettle();
    expect(server.announcements, hasLength(1));

    server.address = '10.0.0.7';
    await tester.pump(_addressRefresh);
    await tester.pumpAndSettle();
    expect(server.announcements, hasLength(2));
    expect(server.announcements.first.stopped, isTrue);
    expect(server.announcements.last.stopped, isFalse);

    server.address = null;
    await tester.pump(_addressRefresh);
    await tester.pumpAndSettle();
    expect(server.announcements, hasLength(2));
    expect(server.announcements.last.stopped, isTrue);

    await _closeCamera(tester);
  });
}

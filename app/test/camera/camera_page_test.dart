import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/camera/capture_layer.dart';
import 'package:instant_replay/features/server/api_server.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_capture_layer.dart';
import 'fake_server_platform.dart';

Future<SharedPreferences> _pumpCamera(
  WidgetTester tester,
  FakeCaptureLayer fake, {
  double height = 1080,
  FakeServerPlatform? server,
}) async {
  // A landscape phone; tests that read the whole status panel use a taller view.
  tester.view.physicalSize = Size(2400, height);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'role': 'camera'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(Capabilities.nativeAndroid),
      captureLayerProvider.overrideWithValue(fake),
      serverPlatformProvider.overrideWithValue((server ?? FakeServerPlatform()).platform),
    ],
    child: const InstantReplayApp(),
  ));
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.localesTestValue = const [Locale('en')]);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  testWidgets('asks for permissions and auto-starts the default profile', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake);

    expect(fake.calls.take(2), ['cameraPermission', 'notificationPermission']);
    expect(fake.starts, ['1080p30']);
    expect(find.byType(Texture), findsOneWidget);
    expect(find.text('1080p30 · 20 Mbps'), findsOneWidget);
  });

  testWidgets('falls back to the first profile without 1080p30', (tester) async {
    final fake = FakeCaptureLayer(profiles: [profile('720p30', width: 1280, height: 720), profile('1080p60', fps: 60)]);
    await _pumpCamera(tester, fake);
    expect(fake.starts, ['720p30']);
  });

  testWidgets('starts even when notifications are denied', (tester) async {
    final fake = FakeCaptureLayer(notificationsGranted: false);
    await _pumpCamera(tester, fake);
    expect(fake.starts, ['1080p30']);
    expect(find.textContaining('Notifications are off'), findsOneWidget);
  });

  testWidgets('shows a retry when camera permission is denied', (tester) async {
    final fake = FakeCaptureLayer(cameraGranted: false);
    await _pumpCamera(tester, fake);
    expect(fake.starts, isEmpty);
    expect(find.text('InstantReplay needs camera permission to record.'), findsOneWidget);

    fake.cameraGranted = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(fake.starts, ['1080p30']);
  });

  testWidgets('changing the profile restarts capture', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake);

    await tester.tap(find.byKey(const Key('camera-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080p60 · 20 Mbps').last);
    await tester.pumpAndSettle();

    expect(fake.calls.where((c) => c == 'stop' || c.startsWith('start:')), ['start:1080p30', 'stop', 'start:1080p60']);
  });

  testWidgets('shows stats from the stream', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake, height: 2400);

    fake.statsController.add(stats(plugged: false));
    await tester.pumpAndSettle();
    expect(find.text('30.0 fps'), findsOneWidget);
    expect(find.text('42 s · 100 MB'), findsOneWidget);
    expect(find.text('3 clips · 30 MB'), findsOneWidget);
    expect(find.text('36.5 °C · 80 % · not charging'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Not charging. Connect power for long sessions.'), findsOneWidget);
  });

  testWidgets('operating mode turns the preview off and a tap brings it back', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake);
    fake.statsController.add(stats());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start operating'));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'preview:false');
    expect(find.byType(Texture), findsNothing);
    expect(find.text('REC · buffer 42 s · outbox 3 · 36.5 °C'), findsOneWidget);

    await tester.tap(find.byKey(const Key('camera-operating')));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'preview:true');
    expect(find.byType(Texture), findsOneWidget);
    expect(fake.starts, ['1080p30'], reason: 'operating mode must not restart capture');
  });

  testWidgets('camera errors are shown until dismissed', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake);

    fake.errorsController.add('Camera device disconnected');
    await tester.pumpAndSettle();
    expect(find.text('Camera errors'), findsOneWidget);
    expect(find.text('Camera device disconnected'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Camera device disconnected'), findsNothing);
  });

  testWidgets('a failed start is shown with a retry', (tester) async {
    final fake = FakeCaptureLayer()..startError = Exception('encoder missing');
    await _pumpCamera(tester, fake);
    expect(find.textContaining('The camera could not start'), findsOneWidget);
    expect(find.textContaining('encoder missing'), findsOneWidget);

    fake.startError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('switching role stops capture', (tester) async {
    final fake = FakeCaptureLayer();
    final prefs = await _pumpCamera(tester, fake);

    await tester.tap(find.byTooltip('Switch role'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a role'), findsOneWidget);
    expect(fake.calls.last, 'stop');
    expect(prefs.getString('role'), isNull);
  });

  group('pairing', () {
    testWidgets('shows the QR, the code, the URL and the viewer count once capture runs', (tester) async {
      final server = FakeServerPlatform();
      await _pumpCamera(tester, FakeCaptureLayer(), server: server, height: 2400);

      final api = server.last!;
      expect(api.started, isTrue);
      final secrets = api.config.secrets;
      expect(secrets.code, matches(RegExp(r'^\d{6}$')));
      expect(secrets.token, matches(RegExp(r'^[0-9a-f]{32}$')));

      final url = 'http://192.168.43.1:8080/?k=${secrets.token}';
      expect(find.text('${secrets.code.substring(0, 3)} ${secrets.code.substring(3)}'), findsOneWidget);
      expect(find.text(url), findsOneWidget);
      expect(tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel, url);
      expect(find.text('No viewers connected'), findsOneWidget);

      api.viewers.add(2);
      await tester.pumpAndSettle();
      expect(find.text('2 viewers connected'), findsOneWidget);
    });

    testWidgets('/info reports the camera id, device name and current profile', (tester) async {
      final server = FakeServerPlatform();
      final prefs = await _pumpCamera(tester, FakeCaptureLayer(), server: server);

      final info = server.last!.config.cameraInfo();
      expect(info.protocolVersion, 1);
      expect(info.name, 'Test Phone');
      expect(info.profileId, '1080p30');
      expect(info.cameraId, prefs.getString('cameraId'));
      expect(info.cameraId, isNotEmpty);
    });

    testWidgets('says so when there is no Wi-Fi or hotspot', (tester) async {
      await _pumpCamera(tester, FakeCaptureLayer(), server: FakeServerPlatform(address: null), height: 2400);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('No Wi-Fi or hotspot found'), findsOneWidget);
    });

    testWidgets('a profile change keeps the server and its token', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, server: server);

      await tester.tap(find.byKey(const Key('camera-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p60 · 20 Mbps').last);
      await tester.pumpAndSettle();

      expect(fake.starts, ['1080p30', '1080p60']);
      expect(server.servers, hasLength(1));
      expect(server.last!.closed, isFalse);
      expect(server.last!.config.cameraInfo().profileId, '1080p60');
      // Viewers are told to renegotiate their live view.
      expect(server.last!.restarts, 1);
    });

    testWidgets('the operating line shows the viewer count', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, server: server);
      server.last!.viewers.add(1);
      await tester.tap(find.text('Start operating'));
      await tester.pumpAndSettle();
      expect(find.text(' · 1 viewer'), findsOneWidget);
    });

    testWidgets('leaving the Camera role stops the server', (tester) async {
      final server = FakeServerPlatform();
      await _pumpCamera(tester, FakeCaptureLayer(), server: server);

      await tester.tap(find.byTooltip('Switch role'));
      await tester.pumpAndSettle();
      expect(server.last!.closed, isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/camera/capture_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_capture_layer.dart';

Future<SharedPreferences> _pumpCamera(WidgetTester tester, FakeCaptureLayer fake, {double height = 1080}) async {
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
}

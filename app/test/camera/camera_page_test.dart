import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/camera/camera_page.dart';
import 'package:instant_replay/features/camera/camera_session.dart';
import 'package:instant_replay/features/camera/capture_layer.dart';
import 'package:instant_replay/features/server/api_server.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:replay_capture_android/replay_capture_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_capture_layer.dart';
import 'fake_server_platform.dart';

Future<SharedPreferences> _pumpCamera(
  WidgetTester tester,
  FakeCaptureLayer fake, {
  double height = 1080,
  double width = 2400,
  FakeServerPlatform? server,
  Map<String, Object> saved = const {},
}) async {
  // A landscape phone; tests that read the whole status panel use a taller view.
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'role': 'camera', ...saved});
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

/// Opens the collapsed "Advanced" section (profile, statistics, diagnostics).
Future<void> _openAdvanced(WidgetTester tester) => _tapVisible(tester, find.text('Advanced'));

/// Scrolls the setup panel to [finder] first: on a landscape phone it may be below the fold.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  // The panel is a lazy ListView: on a small screen the target may not be built yet.
  final panel = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(finder, 100, scrollable: panel);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The Camera's own recording buttons (on the preview in setup, on the black operating screen).
Finder _rec(String name) => find.byKey(Key('camera-rec-$name'));

Future<void> _tapNow(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _operating(WidgetTester tester) => find.byKey(const Key('camera-operating')).evaluate().isNotEmpty;

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.localesTestValue = const [Locale('en')]);
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearLocalesTestValue());

  testWidgets('asks for permissions and auto-starts the default profile', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake);

    expect(fake.calls.take(2), ['cameraPermission', 'notificationPermission']);
    expect(fake.starts, ['1080p30']);
    expect(find.byType(Texture), findsOneWidget);
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
    await _openAdvanced(tester);

    await _tapVisible(tester, find.byKey(const Key('camera-profile')));
    await tester.tap(find.text('1080p60 · 20 Mbps · 9.0 GB/h').last);
    await tester.pumpAndSettle();

    expect(fake.calls.where((c) => c == 'stop' || c.startsWith('start:')), ['start:1080p30', 'stop', 'start:1080p60']);
  });

  testWidgets('the chosen profile is remembered for the next session', (tester) async {
    final eight = CaptureProfile(id: '1080p30-8m', width: 1920, height: 1080, fps: 30, bitrate: 8000000);
    final fake = FakeCaptureLayer(profiles: [profile('1080p30'), eight]);
    final prefs = await _pumpCamera(tester, fake);
    await _openAdvanced(tester);
    await _tapVisible(tester, find.byKey(const Key('camera-profile')));
    await tester.tap(find.text('1080p30 · 8 Mbps · 3.6 GB/h').last);
    await tester.pumpAndSettle();
    expect(fake.starts, ['1080p30', '1080p30-8m']);
    expect(prefs.getString('camera.profile'), '1080p30-8m');

    await tester.pumpWidget(const SizedBox());
    final next = FakeCaptureLayer(profiles: [profile('1080p30'), eight]);
    await _pumpCamera(tester, next, saved: {'camera.profile': '1080p30-8m'});
    expect(next.starts, ['1080p30-8m']);
  });

  testWidgets('a remembered profile the device lacks falls back to the default', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake, saved: {'camera.profile': '1080p30-8m'});
    expect(fake.starts, ['1080p30']);
  });

  testWidgets('shows stats from the stream', (tester) async {
    final fake = FakeCaptureLayer();
    await _pumpCamera(tester, fake, height: 2400);

    fake.statsController.add(stats(plugged: false));
    await tester.pumpAndSettle();
    await _openAdvanced(tester);
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

    await _tapVisible(tester, find.text('Dismiss'));
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

  testWidgets('the Advanced section is collapsed and holds the profile selector', (tester) async {
    await _pumpCamera(tester, FakeCaptureLayer());
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.byKey(const Key('camera-profile')), findsNothing);
    expect(find.text('Frame rate'), findsNothing);

    await _openAdvanced(tester);
    expect(find.byKey(const Key('camera-profile')), findsOneWidget);
    expect(find.text('1080p30 · 20 Mbps · 9.0 GB/h'), findsOneWidget);
    expect(find.text('Save test clip (last 20 s)'), findsOneWidget);
  });

  testWidgets('warnings stay visible with Advanced collapsed', (tester) async {
    final fake = FakeCaptureLayer(notificationsGranted: false);
    await _pumpCamera(tester, fake, height: 2400);
    fake.statsController.add(stats(plugged: false));
    fake.thermalController.add(ThermalEvent(status: 2, action: ThermalAction.none));
    fake.errorsController.add('Camera device disconnected');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera-profile')), findsNothing);
    expect(find.text('Not charging. Connect power for long sessions.'), findsOneWidget);
    expect(find.text('The phone is hot (Moderate). Shade it or lower the quality.'), findsOneWidget);
    expect(find.textContaining('Notifications are off'), findsOneWidget);
    expect(find.text('Camera device disconnected'), findsOneWidget);
  });

  testWidgets('fits a small landscape phone (640x360) in both modes', (tester) async {
    final server = FakeServerPlatform();
    final fake = FakeCaptureLayer(notificationsGranted: false);
    // 1600x900 physical at 2.5 = 640x360 logical.
    await _pumpCamera(tester, fake, width: 1600, height: 900, server: server);
    fake.statsController.add(stats(plugged: false));
    fake.thermalController.add(ThermalEvent(status: 3, action: ThermalAction.none));
    fake.errorsController.add('Camera device disconnected');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera-pairing-code')), findsOneWidget);
    await _openAdvanced(tester);
    expect(tester.takeException(), isNull);

    server.last!.viewers.add(3);
    await tester.pumpAndSettle();
    expect(_operating(tester), isTrue);
    expect(find.text('Severe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('full-session recording', () {
    testWidgets('recovers crashed recordings on entry, before the first start, with a note', (tester) async {
      final old = RecordingSaved(
          name: 'InstantReplay_old.mp4', parts: 1, durationMs: 47 * 60000, bytes: 1, reason: RecordingEnd.recovered);
      final fake = FakeCaptureLayer()..toRecover = [old];
      await _pumpCamera(tester, fake, height: 2400);

      expect(fake.calls.where((c) => c == 'recoverRecordings' || c.startsWith('start:')),
          ['recoverRecordings', 'start:1080p30']);
      expect(find.text('Recovered a 47 min recording'), findsOneWidget);

      // The same file announced again by the recorder's event is not a second note.
      fake.recordingSavedController.add(old);
      await tester.pumpAndSettle();
      expect(find.text('Recovered a 47 min recording'), findsOneWidget);

      await _tapVisible(
          tester, find.descendant(of: find.byKey(const Key('camera-recovered')), matching: find.text('Dismiss')));
      expect(find.text('Recovered a 47 min recording'), findsNothing);
    });

    testWidgets('starts idle; Record, Pause and Finish with a confirmation', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);
      expect(find.text('Full recording'), findsOneWidget);
      expect(_rec('pause'), findsNothing);
      expect(_rec('finish'), findsNothing);
      expect(fake.calls.where((c) => c.startsWith('record')), isEmpty, reason: 'the session starts paused');

      await _tapNow(tester, _rec('record'));
      expect(fake.calls.last, 'recordStart:0');
      expect(_rec('pause'), findsOneWidget);

      fake.statsController.add(stats(recording: recStatus(state: RecordingState.recording, elapsedMs: 754000, parts: 2)));
      await tester.pumpAndSettle();
      expect(find.text('12:34 · part 2'), findsOneWidget);
      expect(find.text('10 h left'), findsOneWidget);

      await _tapNow(tester, _rec('pause'));
      expect(fake.calls.last, 'recordPause');
      expect(find.textContaining('Paused'), findsOneWidget);

      // Finish asks first; "Keep recording" changes nothing.
      await _tapNow(tester, _rec('finish'));
      expect(find.text('Finish the recording?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-finish-keep')));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c == 'recordStop'), isEmpty);

      await _tapNow(tester, _rec('finish'));
      await tester.tap(find.byKey(const ValueKey('rec-finish-confirm')));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStop');
      expect(find.textContaining('Recording saved to the camera'), findsOneWidget);
      expect(_rec('finish'), findsNothing);
    });

    testWidgets('Record and Resume can include the last 30 s from the menu or a long-press', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);

      await _tapNow(tester, _rec('record-menu'));
      expect(find.text('Record including the last 30 s'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-include-30')));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStart:30');

      await _tapNow(tester, _rec('pause'));
      await tester.longPress(_rec('record'));
      await tester.pumpAndSettle();
      expect(find.text('Resume including the last 30 s'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-include-30')));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStart:30');
    });

    testWidgets('no space to start is explained', (tester) async {
      final fake = FakeCaptureLayer()..recordStartError = PlatformException(code: 'no_space');
      await _pumpCamera(tester, fake, height: 2400);
      await _tapNow(tester, _rec('record'));
      expect(find.text('Not enough space on the camera to record (it needs 1 GB free)'), findsOneWidget);
    });

    testWidgets('warns on low space and tells when the Camera stopped for it', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);
      fake.recordingController
          .add(recStatus(state: RecordingState.recording, elapsedMs: 60000, remainingMs: 8 * 60000, lowSpace: true));
      await tester.pumpAndSettle();
      expect(find.text('Low space: 8 min left'), findsOneWidget);

      fake.recordingSavedController
          .add(RecordingSaved(name: 'a.mp4', parts: 1, durationMs: 3600000, bytes: 1, reason: RecordingEnd.lowSpace));
      await tester.pumpAndSettle();
      expect(find.text('The camera ran out of space: the recording stopped and was saved (1 h)'), findsOneWidget);
    });

    testWidgets('works from the operating screen without waking it', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, server: server);
      server.last!.viewers.add(1);
      await tester.pumpAndSettle();
      expect(_operating(tester), isTrue);

      await tester.tap(_rec('record'));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStart:0');
      expect(_operating(tester), isTrue);

      await tester.tap(_rec('pause'));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordPause');

      await tester.tap(_rec('finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-finish-confirm')));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStop');
      expect(_operating(tester), isTrue);
    });

    testWidgets('a profile change keeps the recording going', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake);
      await _tapNow(tester, _rec('record'));
      await _openAdvanced(tester);
      await _tapVisible(tester, find.byKey(const Key('camera-profile')));
      await tester.tap(find.text('1080p60 · 20 Mbps · 9.0 GB/h').last);
      await tester.pumpAndSettle();

      expect(fake.starts, ['1080p30', '1080p60']);
      expect(fake.calls.where((c) => c == 'recordStop' || c == 'recordPause'), isEmpty);
      expect(_rec('pause'), findsOneWidget);
    });

    testWidgets('leaving the Camera finishes the recording, then stops capture', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);
      await _tapNow(tester, _rec('record'));

      await tester.tap(find.byTooltip('Switch role'));
      await tester.pumpAndSettle();
      expect(fake.calls.skipWhile((c) => c != 'recordStop').toList(), ['recordStop', 'stop']);
    });
  });

  group('automatic operating mode', () {
    testWidgets('the first viewer turns the screen black', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, server: server);
      expect(_operating(tester), isFalse);

      server.last!.viewers.add(1);
      await tester.pumpAndSettle();
      expect(_operating(tester), isTrue);
      expect(fake.calls.last, 'preview:false');
      expect(find.byType(Texture), findsNothing);
    });

    testWidgets('is not forced again while viewers stay connected', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, server: server);
      final api = server.last!;
      api.viewers.add(1);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('camera-operating')));
      await tester.pumpAndSettle();
      expect(_operating(tester), isFalse);

      // More viewers join, or one leaves: the coach stays in setup.
      api.viewers.add(2);
      await tester.pumpAndSettle();
      api.viewers.add(1);
      await tester.pumpAndSettle();
      expect(_operating(tester), isFalse);
      expect(fake.calls.last, 'preview:true');

      // The viewer drops and reconnects (screen lock, Wi-Fi blip) right after the coach woke the
      // Camera: it must not blank the screen mid-reframing.
      api.viewers.add(0);
      await tester.pumpAndSettle();
      api.viewers.add(1);
      await tester.pumpAndSettle();
      expect(_operating(tester), isFalse);

      // Long after the wake, everyone left and someone connects again: operating mode once more.
      final container = ProviderScope.containerOf(tester.element(find.byType(CameraPage)));
      container.read(cameraSessionProvider.notifier).lastWokenAt =
          DateTime.now().subtract(autoOperatingQuietPeriod + const Duration(seconds: 1));
      api.viewers.add(0);
      await tester.pumpAndSettle();
      expect(_operating(tester), isFalse);
      api.viewers.add(1);
      await tester.pumpAndSettle();
      expect(_operating(tester), isTrue);
    });
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
      // The first viewers switch to operating mode; a tap wakes the setup screen again.
      await tester.tap(find.byKey(const Key('camera-operating')));
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
      await _openAdvanced(tester);

      await _tapVisible(tester, find.byKey(const Key('camera-profile')));
      await tester.tap(find.text('1080p60 · 20 Mbps · 9.0 GB/h').last);
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
      await tester.pumpAndSettle();
      expect(find.text('1 viewer'), findsOneWidget);
    });

    testWidgets('leaving the Camera role stops the server', (tester) async {
      final server = FakeServerPlatform();
      await _pumpCamera(tester, FakeCaptureLayer(), server: server);

      await tester.tap(find.byTooltip('Switch role'));
      await tester.pumpAndSettle();
      expect(server.last!.closed, isTrue);
    });
  });

  group('broadcast mode', () {
    testWidgets('choosing Broadcast restarts capture in broadcast mode, remembered; viewers renegotiate', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      final prefs = await _pumpCamera(tester, fake, server: server, height: 2400);
      expect(fake.startModes, [false]);
      expect(find.byKey(const Key('camera-broadcast-card')), findsNothing);

      await _openAdvanced(tester);
      await _tapVisible(tester, find.text('Broadcast (beta)'));

      expect(fake.startModes, [false, true]);
      expect(fake.calls.where((c) => c == 'stop' || c.startsWith('start:')), ['start:1080p30', 'stop', 'start:1080p30']);
      expect(prefs.getString('camera.mode'), 'broadcast');
      expect(server.last!.restarts, 1);
      expect(server.last!.config.broadcast!.active, isTrue);
      // Asked while someone is at the Camera; the overlay goes out once capture runs.
      expect(fake.calls, contains('micPermission'));
      expect(fake.overlays, isNotEmpty);
      expect(fake.overlays.last.homeName, 'LOC');
      expect(find.byKey(const Key('camera-broadcast-card')), findsOneWidget);
      expect(find.text('Enter the stream key first'), findsOneWidget);
    });

    testWidgets('a remembered Broadcast mode starts in it; the Camera configures and goes live', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'camera.mode': 'broadcast'});
      expect(fake.startModes, [true]);

      await _tapVisible(tester, find.byKey(const ValueKey('camera-broadcast-settings')));
      await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'abcd-efgh-WXYZ');
      await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ready · 4500 kbps'), findsOneWidget);

      await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-start')));
      expect(fake.broadcastConfigs.single.url, 'rtmp://a.rtmp.youtube.com/live2/abcd-efgh-WXYZ');
      expect(find.text('Connecting…'), findsOneWidget);

      // While streaming, the mode and the profile cannot change (it would cut the stream).
      await _openAdvanced(tester);
      final choice = tester.widget<SegmentedButton<bool>>(find.byKey(const Key('camera-mode-choice')));
      expect(choice.onSelectionChanged, isNull);

      await _tapVisible(tester, find.byKey(const ValueKey('camera-broadcast-stop')));
      await _tapNow(tester, find.byKey(const ValueKey('broadcast-stop-confirm')));
      expect(fake.calls.last, 'broadcastStop');
    });

    testWidgets('the phone keeps the score itself; pairing folds; the controls can be hidden', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'camera.mode': 'broadcast'});
      expect(find.byKey(const Key('camera-scoreboard')), findsOneWidget);
      expect(find.byKey(const Key('camera-pairing-qr')), findsNothing, reason: 'folded');
      expect(find.byKey(const Key('camera-pairing-folded')), findsOneWidget);

      await _tapNow(tester, find.byKey(const ValueKey('score-home-plus')));
      expect(fake.overlays.last.homeScore, 1);

      await _tapNow(tester, find.byKey(const Key('camera-scoreboard-toggle')));
      expect(find.byKey(const Key('camera-scoreboard')), findsNothing);
      expect(find.byKey(const Key('camera-score')), findsOneWidget, reason: 'the score on air instead');
    });

    testWidgets('the operating screen shows the score and the stream', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, saved: {'camera.mode': 'broadcast'});
      await _tapNow(tester, find.text('Start operating'));
      expect(_operating(tester), isTrue);
      expect(find.byKey(const Key('camera-score')), findsOneWidget);
      expect(find.text('0 – 0'), findsOneWidget);
      expect(find.text('Off air'), findsOneWidget);
    });

    testWidgets('a thermal profile fallback does not restart capture while broadcasting', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, saved: {'camera.mode': 'broadcast', 'camera.profile': '1080p60'});
      fake.thermalController.add(ThermalEvent(status: 3, action: ThermalAction.reduceFps));
      await tester.pumpAndSettle();
      expect(fake.starts, ['1080p60']);
    });
  });
}

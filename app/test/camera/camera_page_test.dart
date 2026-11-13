import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/app.dart';
import 'package:instant_replay/features/broadcast/preflight.dart';
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
      streamServerReachableProvider.overrideWithValue((_) async => true),
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

/// The Camera's own recording controls: the button (on the preview in setup, on the black
/// operating screen) and the actions in its dialog.
Finder _rec(String name) => find.byKey(ValueKey('camera-rec-$name'));

/// Opens the recording dialog from its button and picks [action] in it.
Future<void> _recAction(WidgetTester tester, String action) async {
  await tester.tap(_rec('button'));
  await tester.pumpAndSettle();
  await tester.tap(_rec(action));
  await tester.pumpAndSettle();
}

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

    // The replay reserve size goes to the outbox on entry (SPEC §3.4), before anything else.
    // The Camera role keeps no replay reserve: there are no replays on air without a stream.
    expect(fake.calls.take(3), ['reserve:0', 'cameraPermission', 'notificationPermission']);
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
    // Status tiles readable at a glance: memory, clips to send, temperature, battery.
    Finder tile(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));
    expect(tile('camera-op-capture', '42 s'), findsOneWidget);
    expect(tile('camera-op-outbox', '3'), findsOneWidget);
    expect(tile('camera-op-temperature', '36.5 °C'), findsOneWidget);
    expect(tile('camera-op-battery', '80 %'), findsOneWidget);

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
      // A small button; its dialog holds the actions.
      expect(find.byTooltip('Full recording'), findsOneWidget);
      await tester.tap(_rec('button'));
      await tester.pumpAndSettle();
      expect(_rec('pause'), findsNothing);
      expect(_rec('finish'), findsNothing);
      expect(fake.calls.where((c) => c.startsWith('record')), isEmpty, reason: 'the session starts paused');

      await _tapNow(tester, _rec('record'));
      expect(fake.calls.last, 'recordStart:0');

      fake.statsController.add(stats(recording: recStatus(state: RecordingState.recording, elapsedMs: 754000, parts: 2)));
      await tester.pumpAndSettle();
      expect(find.text('12:34'), findsOneWidget, reason: 'the button shows the time');
      await tester.tap(_rec('button'));
      await tester.pumpAndSettle();
      expect(find.text('12:34 · part 2'), findsOneWidget);
      expect(find.text('10 h left'), findsOneWidget);

      await _tapNow(tester, _rec('pause'));
      expect(fake.calls.last, 'recordPause');

      // Finish asks first; "Keep recording" changes nothing.
      await _recAction(tester, 'finish');
      expect(find.text('Finish the recording?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-finish-keep')));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c == 'recordStop'), isEmpty);

      await _recAction(tester, 'finish');
      await tester.tap(find.byKey(const ValueKey('rec-finish-confirm')));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStop');
      expect(find.textContaining('Recording saved to the camera'), findsOneWidget);
    });

    testWidgets('Record and Resume can include the last 30 s', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);

      await tester.tap(_rec('button'));
      await tester.pumpAndSettle();
      expect(find.text('Record including the last 30 s'), findsOneWidget);
      await _tapNow(tester, _rec('record-include'));
      expect(fake.calls.last, 'recordStart:30');

      await _recAction(tester, 'pause');
      await tester.tap(_rec('button'));
      await tester.pumpAndSettle();
      expect(find.text('Resume including the last 30 s'), findsOneWidget);
      await _tapNow(tester, _rec('record-include'));
      expect(fake.calls.last, 'recordStart:30');
    });

    testWidgets('no space to start is explained', (tester) async {
      final fake = FakeCaptureLayer()..recordStartError = PlatformException(code: 'no_space');
      await _pumpCamera(tester, fake, height: 2400);
      await _recAction(tester, 'record');
      expect(find.text('Not enough space on the camera to record (it needs 1 GB free)'), findsOneWidget);
    });

    testWidgets('warns on low space and tells when the Camera stopped for it', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);
      fake.recordingController
          .add(recStatus(state: RecordingState.recording, elapsedMs: 60000, remainingMs: 8 * 60000, lowSpace: true));
      await tester.pumpAndSettle();
      await tester.tap(_rec('button'));
      await tester.pumpAndSettle();
      expect(find.text('Low space: 8 min left'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // close the dialog
      await tester.pumpAndSettle();

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

      await _recAction(tester, 'record');
      expect(fake.calls.last, 'recordStart:0');
      expect(_operating(tester), isTrue);

      await _recAction(tester, 'pause');
      expect(fake.calls.last, 'recordPause');

      await _recAction(tester, 'finish');
      await tester.tap(find.byKey(const ValueKey('rec-finish-confirm')));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'recordStop');
      expect(_operating(tester), isTrue);
    });

    testWidgets('a profile change keeps the recording going', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake);
      await _recAction(tester, 'record');
      await _openAdvanced(tester);
      await _tapVisible(tester, find.byKey(const Key('camera-profile')));
      await tester.tap(find.text('1080p60 · 20 Mbps · 9.0 GB/h').last);
      await tester.pumpAndSettle();

      expect(fake.starts, ['1080p30', '1080p60']);
      expect(fake.calls.where((c) => c == 'recordStop' || c == 'recordPause'), isEmpty);
    });

    testWidgets('leaving the Camera finishes the recording, then stops capture', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400);
      await _recAction(tester, 'record');

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
    testWidgets('the Camera role is replay mode: no mode choice and no replay reserve', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'camera.clipReserve': 5});
      expect(fake.startModes, [false]);
      expect(fake.calls, contains('reserve:0'));
      expect(find.byKey(const Key('camera-broadcast-card')), findsNothing);
      expect(find.byKey(const Key('broadcast-checklist')), findsNothing);
      expect(find.text('Camera'), findsOneWidget);
      await _openAdvanced(tester);
      expect(find.byKey(const Key('camera-mode-choice')), findsNothing);
      expect(find.byKey(const ValueKey('camera-clip-reserve-plus')), findsNothing);
    });

    testWidgets('the Broadcast role starts capture in broadcast mode, with its checklist', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer()..micGranted = false;
      await _pumpCamera(tester, fake, server: server, height: 2400, saved: {'role': 'broadcast'});
      expect(fake.startModes, [true]);
      expect(find.text('Broadcast'), findsNothing, reason: 'no title: the Go live button says it');
      expect(find.byKey(const ValueKey('camera-broadcast-start')), findsOneWidget);
      expect(server.last!.config.broadcast!.active, isTrue);
      expect(fake.calls, isNot(contains('micPermission')), reason: 'asked from the checklist, not on entry');
      expect(fake.overlays, isNotEmpty);

      // The checklist: no key, no microphone yet; each line carries its fix.
      expect(find.byKey(const Key('broadcast-checklist')), findsOneWidget);
      expect(find.text('No YouTube stream key yet'), findsOneWidget);
      expect(find.text('Microphone not allowed: the stream will be silent'), findsOneWidget);
      fake.micGranted = true;
      await _tapVisible(tester, find.byKey(const ValueKey('check-mic-action')));
      expect(fake.calls, contains('micPermission'));
      expect(find.text('Microphone allowed'), findsOneWidget);
      expect(fake.overlays.last.homeName, 'LOC');
      expect(find.byKey(const Key('camera-scoreboard')), findsOneWidget);
      // Without a key, Go live opens the settings.
      expect(find.byKey(const ValueKey('camera-broadcast-start')), findsOneWidget);
      expect(find.byTooltip('Enter the stream key first'), findsOneWidget);
    });

    testWidgets('a remembered Broadcast mode starts in it; the Camera configures and goes live', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'role': 'broadcast'});
      expect(fake.startModes, [true]);

      await _tapVisible(tester, find.byKey(const ValueKey('camera-broadcast-settings')));
      await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'abcd-efgh-WXYZ');
      await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ready · 4500 kbps'), findsOneWidget);

      await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-start')));
      expect(fake.broadcastConfigs.single.url, 'rtmp://a.rtmp.youtube.com/live2/abcd-efgh-WXYZ');
      expect(find.text('Connecting…'), findsOneWidget);

      // Live: the checklist steps aside.
      expect(find.byKey(const Key('broadcast-checklist')), findsNothing);

      await _tapVisible(tester, find.byKey(const ValueKey('camera-broadcast-stop')));
      await _tapNow(tester, find.byKey(const ValueKey('broadcast-stop-confirm')));
      expect(fake.calls.last, 'broadcastStop');
    });

    testWidgets('the phone keeps the score itself; pairing opens in a sheet', (tester) async {
      final server = FakeServerPlatform();
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, server: server, saved: {'role': 'broadcast'});
      // The strip is always there: no toggle to hide it.
      expect(find.byKey(const Key('camera-scoreboard')), findsOneWidget);
      expect(find.byKey(const Key('camera-scoreboard-toggle')), findsNothing);
      expect(find.byKey(const Key('camera-pairing-qr')), findsNothing, reason: 'in the sheet');

      await _tapNow(tester, find.byKey(const ValueKey('score-home-plus')));
      expect(fake.overlays.last.homeScore, 1);

      await _tapVisible(tester, find.byKey(const Key('camera-pairing-open')));
      final code = server.last!.config.secrets.code;
      expect(find.byKey(const Key('camera-pairing-sheet')), findsOneWidget);
      expect(find.text('${code.substring(0, 3)} ${code.substring(3)}'), findsOneWidget);
      expect(find.byKey(const Key('camera-pairing-sheet-qr')), findsOneWidget);
      await _tapNow(tester, find.byKey(const Key('camera-pairing-sheet-close')));
      expect(find.byKey(const Key('camera-pairing-sheet')), findsNothing);
    });

    testWidgets('scoreboard settings: the style is kept and sent with the rest', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'role': 'broadcast'});
      await _tapNow(tester, find.byKey(const Key('camera-scoreboard-settings')));
      await tester.tap(find.byKey(const ValueKey('score-settings-style-plate')));
      await tester.enterText(find.byKey(const ValueKey('score-settings-home-name')), 'leones');
      await tester.pump();
      expect(find.text('6 / 16'), findsOneWidget);
      await _tapNow(tester, find.byKey(const ValueKey('score-settings-save')));
      expect(fake.overlays.last.homeName, 'LEONES');
    });

    testWidgets('a replay on air shows on the broadcast card; speed and Back to live act on the Camera', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'role': 'broadcast', 'broadcast.key': 'abcd'});
      await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-start')));
      expect(find.byKey(const ValueKey('camera-replay')), findsNothing);

      // A viewer put a clip on air.
      final onAir = fake.replayState = ReplayStatus(clipId: 'clip1', speed: 1, positionMs: 0, durationMs: 4000);
      fake.replayController.add(onAir);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('camera-replay')), findsOneWidget);
      expect(find.text('REPLAY ON AIR'), findsOneWidget);
      expect(find.text('0:00 / 0:04'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('camera-replay-speed-0.5')));
      await tester.pump();
      expect(fake.calls.last, 'replaySpeed:0.5');
      await tester.tap(find.byKey(const ValueKey('camera-replay-stop')));
      await tester.pump();
      await tester.pump();
      expect(fake.calls.last, 'replayStop');
      expect(find.byKey(const ValueKey('camera-replay')), findsNothing);
    });

    testWidgets('the replay reserve is set from Advanced and remembered', (tester) async {
      final fake = FakeCaptureLayer();
      final prefs = await _pumpCamera(tester, fake, height: 2400, saved: {'role': 'broadcast'});
      await _openAdvanced(tester);
      await _tapVisible(tester, find.byKey(const ValueKey('camera-clip-reserve-plus')));
      expect(fake.calls.last, 'reserve:4');
      expect(prefs.getInt('camera.clipReserve'), 4);
      for (var i = 0; i < 4; i++) {
        await _tapVisible(tester, find.byKey(const ValueKey('camera-clip-reserve-minus')));
      }
      expect(fake.calls.last, 'reserve:0');
      expect(find.text('Off: the camera deletes each clip once it is on the tablet.'), findsOneWidget);
    });

    testWidgets('zoom: the buttons step it, remembered for the next start; 1× resets', (tester) async {
      final fake = FakeCaptureLayer();
      final prefs = await _pumpCamera(tester, fake, height: 2400);
      await _tapNow(tester, find.byKey(const ValueKey('camera-zoom-in')));
      await _tapNow(tester, find.byKey(const ValueKey('camera-zoom-in')));
      expect(fake.calls.where((c) => c.startsWith('zoom:')), ['zoom:1.25', 'zoom:1.5']);
      expect(find.text('1.5×'), findsOneWidget);
      expect(prefs.getDouble('camera.zoom'), 1.5);
      await _tapNow(tester, find.byKey(const ValueKey('camera-zoom-reset')));
      expect(fake.calls.last, 'zoom:1.0');
    });

    testWidgets('the header mic button mutes and unmutes the stream live, remembered', (tester) async {
      final fake = FakeCaptureLayer();
      final prefs =
          await _pumpCamera(tester, fake, height: 2400, saved: {'role': 'broadcast', 'broadcast.key': 'abcd'});
      await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-start')));
      expect(find.byTooltip('Mute the microphone on air'), findsOneWidget);

      await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-mic')));
      expect(fake.calls, contains('broadcastAudio:false'));
      expect(prefs.getBool('broadcast.audio'), isFalse);
      expect(find.byTooltip('Turn the microphone on air on'), findsOneWidget);

      await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-mic')));
      expect(fake.calls.last, 'broadcastAudio:true');
      expect(find.byTooltip('Mute the microphone on air'), findsOneWidget);
    });

    testWidgets('the operating screen shows the score and the stream', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, saved: {'role': 'broadcast'});
      await _tapVisible(tester, find.text('Black screen'));
      expect(_operating(tester), isTrue);
      expect(find.byKey(const Key('camera-score')), findsOneWidget);
      expect(find.text('0 – 0'), findsOneWidget);
      expect(find.text('Off air'), findsOneWidget);
    });

    testWidgets('a thermal profile fallback does not restart capture while broadcasting', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, saved: {'role': 'broadcast', 'camera.profile': '1080p60'});
      fake.thermalController.add(ThermalEvent(status: 3, action: ThermalAction.reduceFps));
      await tester.pumpAndSettle();
      expect(fake.starts, ['1080p60']);
    });

    // A phone on its side (844×390, 640×360) and a tablet (1180×820), off air and on air.
    for (final size in const [Size(844, 390), Size(640, 360), Size(800, 416), Size(1180, 820), Size(1280, 800)]) {
      testWidgets('broadcasting fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final fake = FakeCaptureLayer();
        await _pumpCamera(tester, fake,
            width: size.width * 2.5, height: size.height * 2.5, saved: {'role': 'broadcast', 'broadcast.key': 'abcd'});
        fake.statsController.add(stats(plugged: false));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        void onScreen(String key) {
          final r = tester.getRect(find.byKey(ValueKey(key)));
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: key);
          expect(r.right, lessThanOrEqualTo(size.width), reason: key);
          expect(r.height, greaterThanOrEqualTo(47.9), reason: key);
        }

        for (final k in ['score-home-plus', 'score-away-plus', 'score-home-minus', 'score-clock-toggle', 'camera-broadcast-start']) {
          onScreen(k);
        }

        await _tapNow(tester, find.byKey(const ValueKey('camera-broadcast-start')));
        fake.broadcastState = BroadcastStatus(
            state: BroadcastState.live, targetKbps: 4500, droppedFrames: 0, audio: false, bitrateKbps: 4400, uptimeMs: 3151000);
        fake.broadcastController.add(fake.broadcastState);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // On air: uptime and bitrate in figures, an explicit Stop, the red microphone row.
        expect(find.textContaining('52:31'), findsOneWidget);
        expect(find.textContaining('4.4'), findsWidgets);
        for (final k in ['camera-broadcast-stop', 'camera-broadcast-mic', 'score-home-plus', 'score-clock-toggle']) {
          onScreen(k);
        }
        expect(find.text('NO SOUND'), findsOneWidget, reason: 'the preview says YouTube hears nothing');
      });
    }

    testWidgets('Prepare the stream: its red button saves and goes live', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, width: 844 * 2.5, height: 390 * 2.5, saved: {'role': 'broadcast'});
      await _tapVisible(tester, find.byKey(const ValueKey('camera-broadcast-settings')));
      expect(find.byKey(const ValueKey('broadcast-config-stepper')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'abcd-efgh');
      for (var i = 0; i < 3; i++) {
        await _tapNow(tester, find.byKey(const ValueKey('broadcast-config-next')));
      }
      // The last step is the checklist, every line shown.
      expect(find.byKey(const ValueKey('check-key')), findsOneWidget);
      expect(find.byKey(const ValueKey('check-key-action')), findsNothing, reason: 'the key is typed on this page');
      expect(tester.takeException(), isNull);
      await _tapNow(tester, find.byKey(const ValueKey('broadcast-config-golive')));
      expect(fake.broadcastConfigs.single.url, 'rtmp://a.rtmp.youtube.com/live2/abcd-efgh');
    });

    testWidgets('once everything is checked the list turns into one green line', (tester) async {
      final fake = FakeCaptureLayer();
      await _pumpCamera(tester, fake, height: 2400, saved: {'role': 'broadcast', 'broadcast.key': 'abcd'});
      fake.statsController.add(stats(plugged: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('broadcast-checklist')), findsNothing);
      expect(find.byKey(const Key('broadcast-checklist-ready')), findsOneWidget);
      expect(find.text('Ready to go live'), findsOneWidget);
    });
  });
}

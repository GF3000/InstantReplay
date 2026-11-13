import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/ui/ir_colors.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/ui/camera_status.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';

LinkState _link(LinkPhase phase, [CameraStatus? status]) => LinkState(phase: phase, status: status);

CameraStatus _status({bool recording = true, int thermal = 0, int? battery, bool? plugged}) => CameraStatus(
      recording: recording,
      fps: 30,
      bufferMs: 60000,
      outboxClips: 2,
      thermalStatus: thermal,
      batteryTempC: 31,
      batteryPercent: battery,
      plugged: plugged,
    );

class _Link extends LinkStateNotifier {
  _Link(this.value);

  final LinkState? value;

  @override
  LinkState? build() => value;
}

Widget _app(LinkState? link) => ProviderScope(
      key: UniqueKey(),
      overrides: [linkStateProvider.overrideWith(() => _Link(link))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(appBar: AppBar(actions: const [CameraStatusIndicator()])),
      ),
    );

void main() {
  test('health: connecting, ok, and each problem', () {
    expect(CameraHealth.of(null).connecting, isTrue);
    expect(CameraHealth.of(_link(LinkPhase.connected, _status())).ok, isTrue);
    expect(CameraHealth.of(_link(LinkPhase.reconnecting, _status())).problems, [CameraProblem.disconnected]);
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(recording: false))).problems, [
      CameraProblem.notRecording,
    ]);
    // Same threshold as the Camera (MODERATE): it degrades capture from there.
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(thermal: 1))).ok, isTrue);
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(thermal: 2))).problems, [CameraProblem.hot]);
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(battery: 15, plugged: false))).problems, [
      CameraProblem.batteryLow,
    ]);
    // Low but charging is fine.
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(battery: 15, plugged: true))).ok, isTrue);
  });

  testWidgets('green REC pill when recording; tap shows the gauges', (tester) async {
    await tester.pumpWidget(_app(_link(LinkPhase.connected, _status(battery: 80, plugged: true))));
    expect(find.text('REC'), findsOneWidget);
    final dot = tester.widget<Container>(find.byKey(const ValueKey('viewer-status-dot')));
    expect((dot.decoration! as BoxDecoration).color, IrColors.dark.ok);
    expect(find.byIcon(Icons.warning_rounded), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('viewer-status'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const ValueKey('viewer-status')));
    await tester.pumpAndSettle();
    expect(find.text('Camera status'), findsWidgets);
    expect(find.text('30 fps'), findsOneWidget);
    expect(find.text('60 s'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('31 °C'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('charging'), findsOneWidget);
    expect(find.byIcon(Icons.battery_charging_full), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pill shows the full recording clock while it runs', (tester) async {
    const status = CameraStatus(
      recording: true,
      fps: 30,
      bufferMs: 60000,
      outboxClips: 0,
      thermalStatus: 0,
      sessionRecording: SessionRecording(
        state: SessionRecordingState.recording,
        elapsedMs: 3151000,
        parts: 1,
        freeBytes: 1,
        lowSpace: false,
      ),
    );
    await tester.pumpWidget(_app(_link(LinkPhase.connected, status)));
    expect(find.text('REC'), findsOneWidget);
    expect(find.text('52:31'), findsOneWidget);
  });

  testWidgets('details include the full-session recording when the Camera sends it', (tester) async {
    const status = CameraStatus(
      recording: true,
      fps: 30,
      bufferMs: 60000,
      outboxClips: 0,
      thermalStatus: 0,
      sessionRecording: SessionRecording(
        state: SessionRecordingState.paused,
        elapsedMs: 754000,
        parts: 1,
        freeBytes: 1,
        lowSpace: true,
        remainingMs: 480000,
      ),
    );
    await tester.pumpWidget(_app(_link(LinkPhase.connected, status)));
    await tester.tap(find.byKey(const ValueKey('viewer-status')));
    await tester.pumpAndSettle();
    expect(find.text('Full recording'), findsOneWidget);
    expect(find.text('Paused · 12:34 · Low space: 8 min left'), findsOneWidget);

    await tester.pumpWidget(_app(_link(LinkPhase.connected, _status())));
    await tester.tap(find.byKey(const ValueKey('viewer-status')));
    await tester.pumpAndSettle();
    expect(find.text('Full recording'), findsNothing);
  });

  testWidgets('problems show a red warning without tapping', (tester) async {
    await tester.pumpWidget(_app(_link(LinkPhase.connected, _status(thermal: 4))));
    expect(find.text('Overheating'), findsOneWidget);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);

    await tester.pumpWidget(_app(_link(LinkPhase.connected, _status(battery: 9, plugged: false, recording: false))));
    expect(find.text('Not recording +1'), findsOneWidget);

    await tester.pumpWidget(_app(_link(LinkPhase.reconnecting)));
    expect(find.text('Disconnected'), findsOneWidget);
  });
}

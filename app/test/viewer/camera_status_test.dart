import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(thermal: 2))).ok, isTrue);
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(thermal: 3))).problems, [CameraProblem.hot]);
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(battery: 15, plugged: false))).problems, [
      CameraProblem.batteryLow,
    ]);
    // Low but charging is fine.
    expect(CameraHealth.of(_link(LinkPhase.connected, _status(battery: 15, plugged: true))).ok, isTrue);
  });

  testWidgets('green REC when recording; tap shows the details with icons', (tester) async {
    await tester.pumpWidget(_app(_link(LinkPhase.connected, _status(battery: 80, plugged: true))));
    expect(find.text('REC'), findsOneWidget);
    final dot = tester.widget<Icon>(find.byIcon(Icons.fiber_manual_record));
    expect(dot.color, CameraStatusIndicator.okColor);

    await tester.tap(find.byKey(const ValueKey('viewer-status')));
    await tester.pumpAndSettle();
    expect(find.text('Camera status'), findsWidgets);
    expect(find.text('30 fps'), findsOneWidget);
    expect(find.text('60 s'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('31 °C'), findsOneWidget);
    expect(find.text('80% · charging'), findsOneWidget);
    expect(find.byIcon(Icons.battery_charging_full), findsOneWidget);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/ui/live_control_view.dart';
import 'package:instant_replay/features/viewer/viewer_page.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ConnectedLink extends LinkStateNotifier {
  @override
  LinkState? build() => const LinkState(
        phase: LinkPhase.connected,
        camera: CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
        status: CameraStatus(recording: true, fps: 30, bufferMs: 60000, outboxClips: 0, thermalStatus: 0),
      );
}

class _RecordingClips extends ViewerClipsNotifier {
  _RecordingClips(this.saved);

  final List<int?> saved;

  @override
  List<SessionClip> build() => const [];

  @override
  void save({int? seconds}) => saved.add(seconds);
}

Widget _app(Widget child, List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('big button saves the default preset; chips save their own duration', (tester) async {
    final saved = <int?>[];
    await tester.pumpWidget(_app(const SaveControls(), [
      linkStateProvider.overrideWith(_ConnectedLink.new),
      viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
    ]));
    expect(find.text('SAVE 20 s'), findsOneWidget);
    expect(find.text('10 s'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('60 s'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('viewer-save'))).height, greaterThanOrEqualTo(56));

    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await tester.tap(find.text('30 s'));
    await tester.tap(find.text('10 s'));
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    expect(saved, [null, 30, 10, null]);
  });

  testWidgets('save is disabled while not connected', (tester) async {
    final saved = <int?>[];
    await tester.pumpWidget(_app(const SaveControls(), [
      linkStateProvider.overrideWith(() => _NullLink()),
      viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
    ]));
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    expect(saved, isEmpty);
  });

  testWidgets('Android without a camera asks for the address, then the code', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_app(const ViewerPage(), [
      sharedPreferencesProvider.overrideWithValue(prefs),
      pageUriProvider.overrideWithValue(null),
    ]));
    expect(find.text('Connect to the camera'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.1.20');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code shown on the camera'), findsOneWidget);
    expect(find.text('Camera at http://192.168.1.20:8080'), findsOneWidget);
  });
}

class _NullLink extends LinkStateNotifier {
  @override
  LinkState? build() => null;
}

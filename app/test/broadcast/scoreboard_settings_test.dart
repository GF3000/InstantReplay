import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/theme.dart';
import 'package:instant_replay/features/broadcast/broadcast_widgets.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';

void main() {
  final state = ScoreboardState.initial;

  Future<Future<ScoreboardSettings?>> open(WidgetTester tester, Size size, {ScoreboardSettings? current}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<ScoreboardSettings?> result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showScoreboardSettingsDialog(context, current ?? state.settings, state: state),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return Future.value(result);
  }

  for (final size in const [Size(360, 640), Size(844, 390), Size(1180, 820)]) {
    testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await open(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('score-settings-preview')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('score-settings-style-plate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('score-settings-style-plate')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Classic counts to 5 and warns that it cuts; Plate counts to 16', (tester) async {
    await open(tester, const Size(1180, 820));
    expect(find.byKey(const ValueKey('score-settings-classic-cut')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('score-settings-home-name')), 'Halcones');
    await tester.pump();
    expect(find.text('8 / 5'), findsOneWidget);
    // The classic preview shows the name cut to 5 letters.
    expect(find.descendant(of: find.byKey(const ValueKey('score-settings-preview')), matching: find.text('HALCO')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('score-settings-style-plate')));
    await tester.pump();
    expect(find.text('8 / 16'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-settings-classic-cut')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('score-settings-preview')), matching: find.text('HALCONES')),
        findsOneWidget);
  });

  testWidgets('names take up to 16 letters; style and size come back with the rest', (tester) async {
    final result = await open(tester, const Size(1180, 820));
    await tester.enterText(find.byKey(const ValueKey('score-settings-home-name')), 'Real Club Deportivo');
    await tester.tap(find.byKey(const ValueKey('score-settings-style-plate')));
    await tester.tap(find.text('Large'));
    await tester.tap(find.byKey(const ValueKey('score-settings-save')));
    await tester.pumpAndSettle();
    final s = (await result)!;
    expect(s.homeName, 'REAL CLUB DEPORT');
    expect(s.homeName.length, ScoreboardState.maxNameLength);
    expect(s.style, ScoreboardStyle.plate);
    expect(s.scale, ScoreboardState.scales[2]);
  });

  testWidgets('a plate board keeps its style when saved without touching it', (tester) async {
    final plate = ScoreboardSettings(
      homeName: 'LEONES',
      awayName: 'HALCONES',
      homeColor: teamPalette[0],
      awayColor: teamPalette[2],
      periods: 2,
      periodMs: 25 * 60000,
      countDown: false,
      style: ScoreboardStyle.plate,
    );
    final result = await open(tester, const Size(1180, 820), current: plate);
    await tester.tap(find.byKey(const ValueKey('score-settings-save')));
    await tester.pumpAndSettle();
    expect((await result)!.style, ScoreboardStyle.plate);
  });
}

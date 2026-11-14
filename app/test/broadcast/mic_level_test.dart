import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/theme.dart';
import 'package:instant_replay/core/ui/ir_widgets.dart';
import 'package:instant_replay/features/broadcast/mic_level.dart';

void main() {
  group('dBFS → meter', () {
    test('−60 dB and quieter is 0, −6 dB and louder is 1, linear in between', () {
      expect(IrMicToggle.levelFromDbfs(null), isNull);
      expect(IrMicToggle.levelFromDbfs(-90), 0);
      expect(IrMicToggle.levelFromDbfs(-60), 0);
      expect(IrMicToggle.levelFromDbfs(-33), closeTo(0.5, 1e-9));
      expect(IrMicToggle.levelFromDbfs(-6), 1);
      expect(IrMicToggle.levelFromDbfs(0), 1);
    });

    test('bars light from the left; the last only near clipping', () {
      expect(IrMicToggle.litBars(0), 0);
      expect(IrMicToggle.litBars(0.01), 1);
      expect(IrMicToggle.litBars(0.25), 1);
      expect(IrMicToggle.litBars(0.26), 2);
      expect(IrMicToggle.litBars(0.6), 3);
      expect(IrMicToggle.litBars(0.76), 4);
      expect(IrMicToggle.litBars(1), 4);
      // Room noise around −50 dB: one bar; speech around −20 dB: three.
      expect(IrMicToggle.litBars(IrMicToggle.levelFromDbfs(-50)!), 1);
      expect(IrMicToggle.litBars(IrMicToggle.levelFromDbfs(-20)!), 3);
    });
  });

  group('IrMicToggle', () {
    Future<void> pump(WidgetTester tester, {required bool open, double? level}) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: Center(child: IrMicToggle(open: open, level: level, onTap: () {}))),
        ));

    testWidgets('no level: just the icon, no bars (no fake animation)', (tester) async {
      await pump(tester, open: true);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byKey(const ValueKey('ir-mic-level')), findsNothing);
      await pump(tester, open: false);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byKey(const ValueKey('ir-mic-level')), findsNothing);
    });

    testWidgets('a level draws the bars, lit as loud as it is; muted too', (tester) async {
      await pump(tester, open: true, level: 0.6);
      expect(find.byKey(const ValueKey('ir-mic-level')), findsOneWidget);
      for (final (i, on) in [(0, 'on'), (1, 'on'), (2, 'on'), (3, 'off')]) {
        expect(find.byKey(ValueKey('ir-mic-bar-$i-$on')), findsOneWidget);
      }
      await pump(tester, open: false, level: 1);
      expect(find.byKey(const ValueKey('ir-mic-level')), findsOneWidget);
      expect(find.byKey(const ValueKey('ir-mic-bar-3-on')), findsOneWidget);
    });
  });

  group('MicLevelPoller', () {
    test('polls only while active and listened to; null otherwise', () async {
      var polls = 0;
      double? db = -20;
      final poller = MicLevelPoller(read: () async {
        polls++;
        return db;
      }, interval: const Duration(milliseconds: 10));
      addTearDown(poller.dispose);
      void listener() {}

      poller.active = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(polls, 0, reason: 'nobody listens');

      poller.addListener(listener);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(polls, greaterThan(0));
      expect(poller.value, -20);
      db = -40;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(poller.value, -40);

      poller.active = false;
      expect(poller.value, isNull);
      final stopped = polls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(polls, stopped);

      poller.active = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      poller.removeListener(listener);
      expect(poller.value, isNull);
      final idle = polls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(polls, idle);
    });
  });
}

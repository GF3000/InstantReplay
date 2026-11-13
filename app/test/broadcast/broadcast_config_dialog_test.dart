import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/broadcast/broadcast_widgets.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_account.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_api.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';

class _FakeAccount implements YouTubeAccount {
  _FakeAccount({this.email, this.current});

  @override
  String? email;

  @override
  YouTubeBroadcast? current;

  final saves = <({String title, YouTubePrivacy privacy, bool fresh})>[];
  YouTubeAccountException? failSave;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> restore() async {}

  @override
  Future<void> signIn() async {
    email = 'coach@example.com';
    _changes.add(null);
  }

  @override
  Future<void> signOut() async => email = null;

  @override
  Future<YouTubeBroadcast?> refresh() async => current;

  @override
  Future<YouTubeIngest?> ingest() async => YouTubeIngest.none;

  @override
  void dispose() {}

  @override
  bool active = false;

  @override
  Future<void> setActive(bool value) async => active = value;

  @override
  Future<YouTubeTarget> ensureLive({required String defaultTitle}) =>
      save(title: defaultTitle, description: '', privacy: YouTubePrivacy.unlisted, fresh: true);

  @override
  Future<YouTubeTarget> save({
    required String title,
    required String description,
    required YouTubePrivacy privacy,
    bool fresh = false,
  }) async {
    if (failSave case final e?) throw e;
    saves.add((title: title, privacy: privacy, fresh: fresh));
    final b = YouTubeBroadcast(
      id: 'b1',
      title: title,
      description: description,
      privacy: privacy,
      lifeCycle: YouTubeLifeCycle.ready,
      scheduledStartTime: null,
    );
    current = b;
    return (server: 'rtmp://a.rtmp.youtube.com/live2', key: 'yt-key-1', broadcast: b);
  }
}

const _info = BroadcastInfo(
  state: BroadcastStreamState.idle,
  configured: false,
  server: BroadcastInfo.defaultServer,
  targetKbps: 4500,
  audio: true,
);

void main() {
  Future<Future<BroadcastConfigResult?>> open(WidgetTester tester,
      {YouTubeAccount? youtube, Size size = const Size(1000, 1400), bool canGoLive = false, Widget? checklist}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<BroadcastConfigResult?> result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result =
                showBroadcastConfigDialog(context, _info, youtube: youtube, canGoLive: canGoLive, checklist: checklist),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return Future.value(result);
  }

  testWidgets('without an account only the stream key shows, as before', (tester) async {
    final result = await open(tester);
    expect(find.byKey(const ValueKey('broadcast-mode')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('broadcast-key')), ' my-key ');
    await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
    await tester.pumpAndSettle();
    final r = (await result)!;
    expect(r.key, 'my-key');
    expect(r.server, BroadcastInfo.defaultServer);
  });

  testWidgets('with an account, key mode is still the default and works', (tester) async {
    final account = _FakeAccount()..active = true;
    final result = await open(tester, youtube: account);
    expect(find.byKey(const ValueKey('broadcast-mode')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'manual');
    await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
    await tester.pumpAndSettle();
    expect((await result)!.key, 'manual');
    // A manual key: Go live no longer prepares a YouTube live.
    expect(account.active, isFalse);
  });

  testWidgets('account mode: sign in, set title and visibility, save gets the key from YouTube', (tester) async {
    final account = _FakeAccount();
    final result = await open(tester, youtube: account);
    await tester.tap(find.byKey(const ValueKey('broadcast-mode-account')));
    await tester.pumpAndSettle();

    // Save waits for the sign-in.
    final save = find.byKey(const ValueKey('broadcast-config-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('youtube-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('coach@example.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('youtube-will-create')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('youtube-title')), 'Coras vs Alcobendas');
    // Visibility: three choice tiles.
    await tester.tap(find.byKey(const ValueKey('youtube-privacy-public')));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(account.saves.single.title, 'Coras vs Alcobendas');
    expect(account.saves.single.privacy, YouTubePrivacy.public);
    expect(account.saves.single.fresh, isTrue);
    final r = (await result)!;
    expect(r.server, 'rtmp://a.rtmp.youtube.com/live2');
    expect(r.key, 'yt-key-1');
  });

  testWidgets('account mode opens on an existing live and updates it', (tester) async {
    final account = _FakeAccount(
      email: 'coach@example.com',
      current: const YouTubeBroadcast(
        id: 'b0',
        title: 'Semifinal',
        description: '',
        privacy: YouTubePrivacy.unlisted,
        lifeCycle: YouTubeLifeCycle.live,
        scheduledStartTime: null,
      ),
    );
    final result = await open(tester, youtube: account);
    expect(find.byKey(const ValueKey('youtube-life')), findsOneWidget);
    expect(find.text('Live on YouTube'), findsOneWidget);
    expect(find.text('YouTube is not receiving anything'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('youtube-title')), 'Semifinal (2nd half)');
    await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
    await tester.pumpAndSettle();
    expect(account.saves.single.fresh, isFalse);
    expect(account.saves.single.title, 'Semifinal (2nd half)');
    expect((await result)!.key, 'yt-key-1');
  });

  testWidgets('a YouTube error stays in the dialog', (tester) async {
    final account = _FakeAccount(email: 'coach@example.com')
      ..failSave = const YouTubeAccountException('live_not_enabled');
    final result = await open(tester, youtube: account);
    await tester.tap(find.byKey(const ValueKey('broadcast-mode-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('youtube-error')), findsOneWidget);
    expect(find.textContaining("can't go live yet"), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('a phone on its side gets a stepper: Save on top, a summary beside', (tester) async {
    final result = await open(tester, youtube: _FakeAccount(), size: const Size(844, 390));
    expect(find.byKey(const ValueKey('broadcast-config-stepper')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final save = tester.getRect(find.byKey(const ValueKey('broadcast-config-save')));
    final key = tester.getRect(find.byKey(const ValueKey('broadcast-key')));
    final summary = tester.getRect(find.byKey(const ValueKey('broadcast-config-summary')));
    expect(save.top, lessThan(52));
    expect(key.right, lessThanOrEqualTo(summary.left));
    expect(tester.takeException(), isNull);

    // Next: picture and sound, with the three presets and the microphone.
    await tester.tap(find.byKey(const ValueKey('broadcast-config-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('broadcast-kbps-6000')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('broadcast-kbps-6000')));
    await tester.pumpAndSettle();
    expect(find.text('6 Mbps'), findsOneWidget, reason: 'the summary follows');
    expect(tester.takeException(), isNull);

    // Without canGoLive (a viewer, or already live) the last step saves.
    await tester.tap(find.byKey(const ValueKey('broadcast-config-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('broadcast-replay-scoreboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('broadcast-config-next')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('broadcast-step-destination')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'landscape-key');
    await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
    await tester.pumpAndSettle();
    final r = (await result)!;
    expect(r.key, 'landscape-key');
    expect(r.targetKbps, 6000);
    expect(r.goLive, isFalse);
  });

  testWidgets('with canGoLive the last step goes live, and Check shows the checklist', (tester) async {
    final result = await open(tester,
        size: const Size(844, 390), canGoLive: true, checklist: const SizedBox(key: ValueKey('the-checklist'), height: 40));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('broadcast-config-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('the-checklist')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('broadcast-config-golive')));
    await tester.pumpAndSettle();
    expect((await result)!.goLive, isTrue);
  });

  testWidgets('a stored key offers to go live as last time', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<BroadcastConfigResult?> result;
    const stored = BroadcastInfo(
      state: BroadcastStreamState.idle,
      configured: true,
      keyHint: 'WXYZ',
      server: BroadcastInfo.defaultServer,
      targetKbps: 2500,
      audio: false,
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showBroadcastConfigDialog(context, stored, canGoLive: true),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('broadcast-config-golive-last')));
    await tester.pumpAndSettle();
    final r = (await result)!;
    expect((r.key, r.targetKbps, r.audio, r.goLive), (null, 2500, false, true));
  });

  testWidgets('the back arrow closes it, saving nothing', (tester) async {
    final result = await open(tester, size: const Size(915, 412));
    await tester.tap(find.byKey(const ValueKey('broadcast-config-back')));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('a tablet gets tabs and the "Before going live" column', (tester) async {
    final result = await open(tester,
        size: const Size(1180, 820), canGoLive: true, checklist: const SizedBox(key: ValueKey('the-checklist'), height: 40));
    expect(find.byKey(const ValueKey('broadcast-config-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('the-checklist')), findsOneWidget);
    expect(find.text('Before going live'), findsOneWidget);
    expect(find.byKey(const ValueKey('broadcast-audio')), findsNothing, reason: 'on the second tab');
    await tester.tap(find.byKey(const ValueKey('broadcast-tab-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('broadcast-audio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('broadcast-kbps-2500')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('broadcast-tab-destination')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'k');
    await tester.tap(find.byKey(const ValueKey('broadcast-config-golive')));
    await tester.pumpAndSettle();
    final r = (await result)!;
    expect((r.key, r.audio, r.targetKbps, r.goLive), ('k', false, 2500, true));
  });

  testWidgets('the live link opens as a QR code', (tester) async {
    final account = _FakeAccount(
      email: 'coach@example.com',
      current: const YouTubeBroadcast(
        id: 'abc123',
        title: 'Final',
        description: '',
        privacy: YouTubePrivacy.public,
        lifeCycle: YouTubeLifeCycle.ready,
        scheduledStartTime: null,
      ),
    );
    await open(tester, youtube: account, size: const Size(915, 412));
    await tester.ensureVisible(find.byKey(const ValueKey('youtube-qr')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('youtube-qr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('youtube-qr-code')), findsOneWidget);
    expect(find.text('https://youtu.be/abc123'), findsWidgets);
    expect(tester.takeException(), isNull);
    // On a phone on its side the whole code fits on screen, with the link and Close beside it.
    final code = tester.getRect(find.byKey(const ValueKey('youtube-qr-code')));
    final close = tester.getRect(find.byKey(const ValueKey('youtube-qr-close')));
    expect(code.top, greaterThanOrEqualTo(0));
    expect(code.bottom, lessThanOrEqualTo(412));
    expect(code.height, greaterThan(300));
    expect(close.left, greaterThan(code.right));
    expect(close.bottom, lessThanOrEqualTo(412));
    // Copy and share sit beside the code too.
    expect(find.byKey(const ValueKey('youtube-qr-share')), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('youtube-qr-share'))).bottom, lessThanOrEqualTo(412));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.byKey(const ValueKey('youtube-qr-copy')));
    await tester.pump();
    expect(copied, 'https://youtu.be/abc123');
    final copy = find.byKey(const ValueKey('youtube-qr-copy'));
    expect(find.descendant(of: copy, matching: find.text('Link copied')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.descendant(of: copy, matching: find.text('Copy link')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('youtube-qr-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('youtube-qr-code')), findsNothing);
  });

  testWidgets('the bar shows a QR button only with an account live', (tester) async {
    var shared = 0;
    Future<void> bar({VoidCallback? onShare}) => tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BroadcastBar(
              info: _info,
              enabled: true,
              keyPrefix: 'b',
              onStart: () {},
              onStop: () {},
              onConfigure: () {},
              onShare: onShare,
            ),
          ),
        ));
    await bar();
    expect(find.byKey(const ValueKey('b-qr')), findsNothing);
    await bar(onShare: () => shared++);
    await tester.tap(find.byKey(const ValueKey('b-qr')));
    expect(shared, 1);
  });
}

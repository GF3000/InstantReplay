import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/broadcast/broadcast_widgets.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_account.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_api.dart';
import 'package:instant_replay/features/viewer/remote_youtube.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';

const _info = BroadcastInfo(
  state: BroadcastStreamState.idle,
  configured: true,
  server: BroadcastInfo.defaultServer,
  targetKbps: 4500,
  audio: true,
  keyHint: '1234',
);

const _live = YouTubeLiveInfo(
  id: 'b1',
  title: 'Final',
  description: 'Copa',
  privacy: 'public',
  lifeCycle: 'ready',
  url: 'https://youtu.be/b1',
);

YouTubeStatus _status({
  YouTubeDestination destination = YouTubeDestination.account,
  String? email = 'coach@example.com',
  String? channel = 'Coras TV',
  YouTubeLiveInfo? live,
}) =>
    YouTubeStatus(
      destination: destination,
      email: email,
      channelId: channel == null ? null : 'UC1',
      channelTitle: channel,
      live: live,
    );

/// The Camera at the other end: records the commands and answers them as [answer] says.
class _Camera {
  _Camera() {
    account = RemoteYouTubeAccount(send: _send, timeout: const Duration(seconds: 5));
  }

  late final RemoteYouTubeAccount account;
  final commands = <YouTubeCmd>[];
  bool connected = true;

  /// The answer to each command; null leaves it unanswered.
  YouTubeResult? Function(YouTubeCmd cmd) answer = (cmd) => YouTubeResult(requestId: cmd.requestId);

  bool _send(WsMessage m) {
    if (!connected) return false;
    final cmd = m as YouTubeCmd;
    commands.add(cmd);
    final reply = answer(cmd);
    if (reply != null) scheduleMicrotask(() => account.onMessage(reply));
    return true;
  }
}

void main() {
  group('RemoteYouTubeAccount', () {
    test('reads the Camera state: channel, email, live, mode; changes only when it differs', () async {
      final camera = _Camera();
      final a = camera.account;
      expect((a.email, a.active, a.current, a.available), (null, false, null, false));
      var changes = 0;
      final sub = a.changes.listen((_) => changes++);
      a.update(_status(live: _live));
      a.update(_status(live: _live));
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      expect((a.displayName, a.displaySub), ('Coras TV', 'coach@example.com'));
      expect(a.active, isTrue);
      expect((a.current!.title, a.current!.privacy, a.current!.lifeCycle), ('Final', YouTubePrivacy.public, YouTubeLifeCycle.ready));
      expect(a.current!.url, 'https://youtu.be/b1');
      await sub.cancel();
    });

    test('save, create and prepare are commands; the answer carries the new state and the server', () async {
      final camera = _Camera()
        ..answer = (cmd) => YouTubeResult(
              requestId: cmd.requestId,
              status: _status(live: YouTubeLiveInfo(
                id: 'b2',
                title: cmd.title ?? 'Match',
                privacy: cmd.privacy ?? 'unlisted',
                lifeCycle: 'ready',
                url: 'https://youtu.be/b2',
              )),
              server: 'rtmp://yt/live2',
            );
      final a = camera.account..update(_status());
      final saved = await a.save(title: 'Final', description: 'Copa', privacy: YouTubePrivacy.private);
      expect(camera.commands.single.action, YouTubeAction.save);
      expect((camera.commands.single.title, camera.commands.single.description, camera.commands.single.privacy),
          ('Final', 'Copa', 'private'));
      expect((saved.server, saved.key, saved.broadcast.id), ('rtmp://yt/live2', '', 'b2'));
      expect(a.current!.title, 'Final');

      await a.save(title: 'Otra', description: '', privacy: YouTubePrivacy.public, fresh: true);
      expect(camera.commands.last.action, YouTubeAction.create);
      final prepared = await a.ensureLive(defaultTitle: 'ignored');
      expect(camera.commands.last.action, YouTubeAction.prepare);
      expect(prepared.broadcast.url, 'https://youtu.be/b2');
    });

    test("the Camera's error comes back as the account's; no Camera is no_camera", () async {
      final camera = _Camera()
        ..answer = (cmd) => YouTubeResult(requestId: cmd.requestId, errorCode: 'quota', errorMessage: 'daily');
      final a = camera.account..update(_status());
      await expectLater(
        a.refresh(),
        throwsA(isA<YouTubeAccountException>().having((e) => e.code, 'code', 'quota')),
      );
      camera.connected = false;
      await expectLater(
        a.ensureLive(defaultTitle: 'x'),
        throwsA(isA<YouTubeAccountException>().having((e) => e.code, 'code', 'no_camera')),
      );
      // A link that drops with a command in flight.
      camera
        ..connected = true
        ..answer = (_) => null;
      final pending = a.refresh();
      a.linkChanged();
      await expectLater(pending, throwsA(isA<YouTubeAccountException>().having((e) => e.code, 'code', 'no_camera')));
    });

    test('saving a key asks the Camera to use it only in account mode without a session', () async {
      final camera = _Camera();
      final a = camera.account..update(_status());
      await a.setActive(false);
      expect(camera.commands, isEmpty, reason: 'signed in: the account wins, the Camera decides');
      a.update(_status(email: null, channel: null));
      await a.setActive(false);
      expect(camera.commands.single.action, YouTubeAction.useKey);
      a.update(_status(destination: YouTubeDestination.key, email: null, channel: null));
      await a.setActive(false);
      expect(camera.commands, hasLength(1));
      expect(() => a.signIn(), throwsUnsupportedError);
    });
  });

  group('Prepare the stream on a viewer', () {
    Future<Future<BroadcastConfigResult?>> open(WidgetTester tester, YouTubeAccount youtube,
        {Size size = const Size(1000, 1400)}) async {
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
              onPressed: () => result = showBroadcastConfigDialog(context, _info, youtube: youtube, remoteYouTube: true),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return Future.value(result);
    }

    testWidgets("the Camera's channel with the email under it; the key is locked with the way out on the Camera",
        (tester) async {
      final camera = _Camera()..answer = (cmd) => YouTubeResult(requestId: cmd.requestId, status: _status(live: _live));
      camera.account.update(_status(live: _live));
      await open(tester, camera.account);
      expect(camera.commands.single.action, YouTubeAction.refresh, reason: 'the live is read again on open');

      expect(find.text('Streams to the YouTube channel Coras TV'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('youtube-account-name'))).data, 'Coras TV');
      expect(tester.widget<Text>(find.byKey(const ValueKey('youtube-email'))).data, 'coach@example.com');
      // Signing in and out happens on the Camera.
      expect(find.byKey(const ValueKey('youtube-sign-out')), findsNothing);
      expect(find.byKey(const ValueKey('youtube-on-camera')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('youtube-title'))).controller!.text, 'Final');

      await tester.tap(find.byKey(const ValueKey('broadcast-mode-key')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('broadcast-key')), findsNothing);
      expect(find.text('The Camera is using its YouTube account. To stream with a key, sign out on the Camera.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('broadcast-key-locked-sign-out')), findsNothing);
    });

    testWidgets('saving title and visibility sends them to the Camera; the key stays there', (tester) async {
      final camera = _Camera()
        ..answer = (cmd) => YouTubeResult(
              requestId: cmd.requestId,
              status: _status(live: _live),
              server: 'rtmp://yt/live2',
            );
      camera.account.update(_status(live: _live));
      final result = await open(tester, camera.account);
      await tester.enterText(find.byKey(const ValueKey('youtube-title')), 'Coras vs Alcobendas');
      await tester.tap(find.byKey(const ValueKey('youtube-privacy-private')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
      await tester.pumpAndSettle();

      final save = camera.commands.last;
      expect(save.action, YouTubeAction.save);
      expect((save.title, save.privacy), ('Coras vs Alcobendas', 'private'));
      final r = (await result)!;
      expect(r.key, isNull, reason: 'null keeps the key on the Camera');
      expect(r.server, 'rtmp://yt/live2');
    });

    testWidgets('New live sends create', (tester) async {
      final camera = _Camera()..answer = (cmd) => YouTubeResult(requestId: cmd.requestId, status: _status(live: _live));
      camera.account.update(_status(live: _live));
      await open(tester, camera.account);
      await tester.tap(find.byKey(const ValueKey('youtube-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
      await tester.pumpAndSettle();
      expect(camera.commands.last.action, YouTubeAction.create);
    });

    testWidgets('no account on the Camera: told to sign in there; a key still works and leaves account mode',
        (tester) async {
      final camera = _Camera();
      camera.account.update(_status(email: null, channel: null));
      final result = await open(tester, camera.account);
      expect(find.byKey(const ValueKey('youtube-remote-sign-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('youtube-sign-in')), findsNothing);
      expect(find.text('Sign in to the YouTube account to stream'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('broadcast-config-save'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('broadcast-mode-key')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('broadcast-key')), 'manual');
      await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
      await tester.pumpAndSettle();
      expect((await result)!.key, 'manual');
      expect(camera.commands.single.action, YouTubeAction.useKey);
    });

    testWidgets('a key on the Camera: the same words as its checklist', (tester) async {
      final camera = _Camera();
      camera.account.update(_status(destination: YouTubeDestination.key, email: null, channel: null));
      await open(tester, camera.account);
      expect(find.text('Streams with a manual key'), findsOneWidget);
      expect(find.byKey(const ValueKey('broadcast-key')), findsOneWidget);
    });

    testWidgets("an error from the Camera says to sign out on the Camera", (tester) async {
      final camera = _Camera()..answer = (cmd) => YouTubeResult(requestId: cmd.requestId, errorCode: 'quota');
      camera.account.update(_status(live: _live));
      await open(tester, camera.account);
      expect(find.byKey(const ValueKey('youtube-error')), findsNothing, reason: 'the refresh on open is quiet');
      await tester.tap(find.byKey(const ValueKey('broadcast-config-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Or sign out on the Camera and stream with a stream key.'), findsOneWidget);
    });
  });

  group('Share the live on a viewer', () {
    Future<void> share(WidgetTester tester, YouTubeAccount youtube) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => shareYouTubeLive(context, youtube, remote: true),
              child: const Text('share'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('share'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets("the Camera's known link shows at once, without asking it", (tester) async {
      final camera = _Camera();
      camera.account.update(_status(live: _live));
      await share(tester, camera.account);
      expect(find.byKey(const ValueKey('youtube-qr-loading')), findsNothing);
      expect(find.textContaining('youtu.be/b1'), findsWidgets);
      expect(camera.commands, isEmpty);
    });

    testWidgets('without a usable live it asks the Camera to prepare one; an error offers Retry', (tester) async {
      final camera = _Camera()..answer = (cmd) => YouTubeResult(requestId: cmd.requestId, errorCode: 'network');
      camera.account.update(_status(live: const YouTubeLiveInfo(
        id: 'old',
        title: 'Ayer',
        privacy: 'public',
        lifeCycle: 'complete',
        url: 'https://youtu.be/old',
      )));
      await share(tester, camera.account);
      await tester.pumpAndSettle();
      expect(camera.commands.single.action, YouTubeAction.prepare);
      expect(find.byKey(const ValueKey('youtube-qr-error')), findsOneWidget);
      expect(find.textContaining('sign out on the Camera'), findsOneWidget);

      camera.answer = (cmd) => YouTubeResult(requestId: cmd.requestId, status: _status(live: _live));
      await tester.tap(find.byKey(const ValueKey('youtube-qr-retry')));
      await tester.pumpAndSettle();
      expect(camera.commands, hasLength(2));
      expect(find.textContaining('youtu.be/b1'), findsWidgets);
    });
  });

  test('Go live errors from the Camera read as YouTube errors with the way out on the Camera', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(broadcastErrorMessage(en, 'youtube_quota', null), endsWith('Or sign out on the Camera and stream with a stream key.'));
    expect(broadcastErrorMessage(en, 'youtube_not_signed_in', null), contains('sign in again on the Camera'));
    final es = lookupAppLocalizations(const Locale('es'));
    expect(youtubeErrorMessage(es, const YouTubeAccountException('forbidden'), remote: true),
        endsWith('O cierra sesión en la cámara y emite con una clave de emisión.'));
  });
}

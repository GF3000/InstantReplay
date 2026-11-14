import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/ui/clip_list.dart';
import 'package:instant_replay/features/viewer/ui/live_control_view.dart';
import 'package:instant_replay/features/viewer/ui/review_page.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'fakes.dart';
import 'review_page_test.dart' show FakeVideo;

const _live = BroadcastInfo(
  state: BroadcastStreamState.live,
  configured: true,
  server: BroadcastInfo.defaultServer,
  targetKbps: 4500,
  audio: true,
);

const _idle = BroadcastInfo(
  state: BroadcastStreamState.idle,
  configured: true,
  server: BroadcastInfo.defaultServer,
  targetKbps: 4500,
  audio: true,
);

/// A Camera in broadcast mode with [stream], and [replay] on air.
class _Link extends LinkStateNotifier {
  _Link({this.stream = _live, this.replay});

  final BroadcastInfo? stream;
  final ReplayInfo? replay;

  @override
  LinkState? build() => _state(replay);

  LinkState _state(ReplayInfo? replay) => LinkState(
    phase: LinkPhase.connected,
    camera: const CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
    status: CameraStatus(
      recording: true,
      fps: 30,
      bufferMs: 60000,
      outboxClips: 0,
      thermalStatus: 0,
      scoreboard: stream == null ? null : ScoreboardState.initial,
      broadcast: stream,
      replay: replay,
    ),
  );

  /// The Camera reports [replay] on air (null: back to live).
  void report(ReplayInfo? replay) => state = _state(replay);
}

/// Records what the replay controls send.
class _Remote extends ViewerBroadcastNotifier {
  _Remote([List<Object>? sent]) : sent = sent ?? [];

  /// Shared by every instance the (auto-disposed) provider creates during a test.
  final List<Object> sent;

  @override
  BroadcastNotice? build() => null;

  @override
  bool replayAir(String clipId, {double speed = 1}) {
    sent.add(ReplayAir(clipId: clipId, speed: speed).encode());
    return true;
  }

  @override
  bool replaySpeed(double speed) {
    sent.add(ReplaySpeed(speed: speed).encode());
    return true;
  }

  @override
  bool replayStop() {
    sent.add(const ReplayStop().encode());
    return true;
  }
}

class _NoLive extends LiveViewNotifier {
  @override
  LiveViewState build() => const LiveViewState(phase: LivePhase.playing);
}

class _NoClips extends ViewerClipsNotifier {
  @override
  List<SessionClip> build() => const [];
}

class _PlayableClip extends MemoryClip {
  _PlayableClip(super.clipId, super.length);

  @override
  VideoPlayerController createPlayer() => FakeVideo();
}

SessionClip _clip({bool onCamera = true}) => SessionClip(
  requestId: 'r1',
  seconds: 20,
  requestedAt: DateTime(2026, 11, 9, 18, 30),
  phase: SessionClipPhase.ready,
  clipId: 'c1',
  durationMs: 20000,
  stored: _PlayableClip('c1', 10),
  onCamera: onCamera,
);

Future<_Remote> _pump(
  WidgetTester tester,
  Widget child, {
  LinkStateNotifier Function()? link,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final remote = _Remote();
  // The provider is auto-disposed between screens: each rebuild gets a fresh notifier that
  // records into the same list.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        linkStateProvider.overrideWith(link ?? _Link.new),
        liveViewProvider.overrideWith(_NoLive.new),
        viewerClipsProvider.overrideWith(_NoClips.new),
        viewerBroadcastNoticeProvider.overrideWith(() => _Remote(remote.sent)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  return remote;
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  group('a tap on a clip', () {
    testWidgets('while streaming, opens the review on the tablet only, with Air replay', (tester) async {
      final remote = await _pump(tester, ClipTile(clip: _clip()));
      await tester.tap(find.byType(ClipTile));
      await tester.pumpAndSettle();
      // No question first: reviewing never goes on air by itself.
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(ReviewPage), findsOneWidget);
      expect(remote.sent, isEmpty);
      expect(_key('review-air'), findsOneWidget);
      expect(find.text('Air replay'), findsOneWidget);
    });

    for (final (name, clip, link) in [
      ('a clip no longer on the Camera', _clip(onCamera: false), _Link.new),
      ('without an active stream', _clip(), () => _Link(stream: _idle)),
      ('in replay mode', _clip(), () => _Link(stream: null)),
    ]) {
      testWidgets('$name opens without Air replay', (tester) async {
        final remote = await _pump(tester, ClipTile(clip: clip), link: link);
        await tester.tap(find.byType(ClipTile));
        await tester.pumpAndSettle();
        expect(find.byType(ReviewPage), findsOneWidget);
        expect(_key('review-air'), findsNothing);
        expect(remote.sent, isEmpty);
      });
    }
  });

  group('Air replay on the review page', () {
    const onAir = ReplayInfo(clipId: 'c1', speed: 0.5, positionMs: 0, durationMs: 20000);

    Future<(_Remote, _Link)> open(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
      late _Link link;
      final remote = await _pump(
        tester,
        ReviewPage(clip: _clip(), replayBar: true),
        link: () => link = _Link(),
        size: size,
      );
      await tester.pumpAndSettle();
      return (remote, link);
    }

    Finder speed(String label) => find.descendant(of: _key('review-speed'), matching: find.text(label));

    testWidgets('sends the clip at the current speed; the tablet then mirrors the stream', (tester) async {
      final (remote, link) = await open(tester);
      await tester.tap(speed('0.5×'));
      await tester.pumpAndSettle();
      // Before it goes on air, the speed is the tablet's own.
      expect(remote.sent, isEmpty);

      await tester.tap(_key('review-air'));
      await tester.pumpAndSettle();
      expect(remote.sent, [const ReplayAir(clipId: 'c1', speed: 0.5).encode()]);

      link.report(onAir);
      await tester.pumpAndSettle();
      expect(_key('review-on-air'), findsOneWidget);
      expect(find.text('REPLAY ON AIR'), findsOneWidget);
      // One speed control for both: the bar has none of its own.
      expect(_key('viewer-replay-stop'), findsOneWidget);
      expect(_key('viewer-replay-speed'), findsNothing);
      // One red button on air: Back to live, no separate Take off air.
      expect(_key('review-air'), findsNothing);
      expect(find.text('Take off air'), findsNothing);

      await tester.tap(speed('1×'));
      await tester.pumpAndSettle();
      expect(remote.sent.last, const ReplaySpeed(speed: 1).encode());

      // Back to live: the stream leaves the replay.
      await tester.tap(_key('viewer-replay-stop'));
      await tester.pumpAndSettle();
      expect(remote.sent.last, const ReplayStop().encode());
    });

    testWidgets('on a phone the button keeps only its icon', (tester) async {
      final (remote, _) = await open(tester, size: const Size(360, 640));
      expect(find.text('Air replay'), findsNothing);
      await tester.tap(_key('review-air'));
      await tester.pumpAndSettle();
      expect(remote.sent, [const ReplayAir(clipId: 'c1').encode()]);
    });

    testWidgets('leaving the page after airing it goes back to live', (tester) async {
      late _Link link;
      final remote = await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(ReviewPage.route(_clip(), replayBar: true)),
            child: const Text('open'),
          ),
        ),
        link: () => link = _Link(),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(_key('review-air'));
      await tester.pumpAndSettle();
      link.report(onAir);
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(remote.sent.last, const ReplayStop().encode());
    });

    testWidgets('Back to live on air takes the replay off and returns the tablet to live', (tester) async {
      late _Link link;
      final remote = await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(ReviewPage.route(_clip(), replayBar: true)),
            child: const Text('open'),
          ),
        ),
        link: () => link = _Link(),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(_key('review-air'));
      await tester.pumpAndSettle();
      link.report(onAir);
      await tester.pumpAndSettle();
      await tester.tap(_key('viewer-replay-stop'));
      await tester.pumpAndSettle();
      expect(remote.sent.last, const ReplayStop().encode());
      expect(find.byType(ReviewPage), findsNothing);
    });
  });

  group('the replay bar', () {
    const onAir = ReplayInfo(clipId: 'c1', speed: 1, positionMs: 5000, durationMs: 20000);

    testWidgets('shows the clip on air for every viewer; speed and Back to live go to the Camera', (tester) async {
      final remote = await _pump(tester, const LiveControlView(), link: () => _Link(replay: onAir));
      expect(find.text('REPLAY ON AIR'), findsOneWidget);
      expect(find.text('0:05 / 0:20'), findsOneWidget);
      // The position advances locally at the replay speed.
      await tester.pump(const Duration(seconds: 2));
      expect(_key('viewer-replay-time'), findsOneWidget);

      await tester.tap(_key('viewer-replay-speed-0.5'));
      await tester.pump();
      await tester.tap(_key('viewer-replay-stop'));
      await tester.pump();
      expect(remote.sent, [const ReplaySpeed(speed: 0.5).encode(), const ReplayStop().encode()]);
    });

    testWidgets('nothing while the program shows the camera', (tester) async {
      await _pump(tester, const LiveControlView());
      expect(_key('viewer-replay'), findsNothing);
    });

    testWidgets('on the review page while its clip is on air', (tester) async {
      await _pump(
        tester,
        ReviewPage(clip: _clip(), replayBar: true),
        link: () => _Link(replay: onAir),
      );
      expect(_key('viewer-replay-stop'), findsOneWidget);
    });

    testWidgets('not on the review page of another clip', (tester) async {
      await _pump(
        tester,
        ReviewPage(clip: _clip(), replayBar: true),
        link: () => _Link(replay: const ReplayInfo(clipId: 'other', speed: 1, positionMs: 0, durationMs: 1000)),
      );
      expect(_key('viewer-replay-stop'), findsNothing);
    });

    for (final size in const [Size(360, 640), Size(640, 360), Size(768, 1024), Size(1280, 800), Size(800, 1280)]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
        // Under a 48 px app bar, as in the app.
        await _pump(
          tester,
          const Column(
            children: [
              SizedBox(height: 48),
              Expanded(child: LiveControlView()),
            ],
          ),
          link: () => _Link(replay: onAir),
          size: size,
        );
        expect(tester.takeException(), isNull);
        for (final k in ['viewer-replay-stop', 'viewer-replay-speed-0.25', 'viewer-save', 'score-home-plus']) {
          final r = tester.getRect(_key(k));
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: k);
          expect(r.right, lessThanOrEqualTo(size.width), reason: k);
        }
        expect(tester.getRect(_key('viewer-replay-stop')).height, greaterThanOrEqualTo(47.9));
      });
    }
  });

  testWidgets('on air from the review page: one speed for tablet and stream, leaving goes back to live', (tester) async {
    const onAir = ReplayInfo(clipId: 'c1', speed: 1, positionMs: 0, durationMs: 20000);
    final remote = await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(ReviewPage.route(_clip(), replayBar: true, onAir: true)),
          child: const Text('open'),
        ),
      ),
      link: () => _Link(replay: onAir),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The on-air bar has no speed of its own: the review page's control drives both.
    expect(_key('viewer-replay-stop'), findsOneWidget);
    expect(_key('viewer-replay-speed'), findsNothing);
    await tester.tap(find.descendant(of: _key('review-speed'), matching: find.text('0.5×')));
    await tester.pumpAndSettle();
    expect(remote.sent, [const ReplaySpeed(speed: 0.5).encode()]);

    // Leaving the page cuts back to live.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReviewPage), findsNothing);
    expect(remote.sent.last, const ReplayStop().encode());
  });

  testWidgets('Back to live on the review page stops the replay and closes the page', (tester) async {
    const onAir = ReplayInfo(clipId: 'c1', speed: 1, positionMs: 0, durationMs: 20000);
    final remote = await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(ReviewPage.route(_clip(), replayBar: true, onAir: true)),
          child: const Text('open'),
        ),
      ),
      link: () => _Link(replay: onAir),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(_key('viewer-replay-stop'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewPage), findsNothing);
    expect(remote.sent.where((m) => m == const ReplayStop().encode()), hasLength(1), reason: 'not twice');
  });
}

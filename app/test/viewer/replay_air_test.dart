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
  LinkState? build() => LinkState(
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
}

/// Records what the replay controls send.
class _Remote extends ViewerBroadcastNotifier {
  final sent = <Object>[];

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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        linkStateProvider.overrideWith(link ?? _Link.new),
        liveViewProvider.overrideWith(_NoLive.new),
        viewerClipsProvider.overrideWith(_NoClips.new),
        viewerBroadcastNoticeProvider.overrideWith(() => remote),
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
    testWidgets('while streaming, a clip on the Camera asks; "Also on air" sends it and opens it', (tester) async {
      final remote = await _pump(tester, ClipTile(clip: _clip()));
      await tester.tap(find.byType(ClipTile));
      await tester.pumpAndSettle();
      expect(find.text('Only on this tablet'), findsOneWidget);
      expect(find.text('Also on air'), findsOneWidget);
      await tester.tap(_key('replay-choice-air'));
      await tester.pumpAndSettle();
      expect(remote.sent, [const ReplayAir(clipId: 'c1').encode()]);
      expect(find.byType(ReviewPage), findsOneWidget);
    });

    testWidgets('"Only on this tablet" opens it without going on air', (tester) async {
      final remote = await _pump(tester, ClipTile(clip: _clip()));
      await tester.tap(find.byType(ClipTile));
      await tester.pumpAndSettle();
      await tester.tap(_key('replay-choice-tablet'));
      await tester.pumpAndSettle();
      expect(remote.sent, isEmpty);
      expect(find.byType(ReviewPage), findsOneWidget);
    });

    testWidgets('dismissing the question opens nothing', (tester) async {
      final remote = await _pump(tester, ClipTile(clip: _clip()));
      await tester.tap(find.byType(ClipTile));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(remote.sent, isEmpty);
      expect(find.byType(ReviewPage), findsNothing);
    });

    for (final (name, clip, link) in [
      ('a clip no longer on the Camera', _clip(onCamera: false), _Link.new),
      ('without an active stream', _clip(), () => _Link(stream: _idle)),
      ('in replay mode', _clip(), () => _Link(stream: null)),
    ]) {
      testWidgets('$name opens at once, without asking', (tester) async {
        final remote = await _pump(tester, ClipTile(clip: clip), link: link);
        await tester.tap(find.byType(ClipTile));
        await tester.pumpAndSettle();
        expect(_key('replay-choice'), findsNothing);
        expect(remote.sent, isEmpty);
        expect(find.byType(ReviewPage), findsOneWidget);
      });
    }
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
}

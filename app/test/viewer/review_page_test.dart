import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/player/frame_timeline.dart';
import 'package:instant_replay/features/viewer/player/player_platform.dart';
import 'package:instant_replay/features/viewer/ui/review_page.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

import 'fakes.dart';

void main() {
  late FakeVideo video;
  late FakePlatform platform;

  Future<void> pump(WidgetTester tester, {FrameTimeline? timeline, SeekRule rule = SeekRule.atOrAfter}) async {
    video = FakeVideo();
    platform = FakePlatform(video, timeline, rule);
    final clip = SessionClip(
      requestId: 'r1',
      seconds: 10,
      requestedAt: DateTime(2026, 10, 30, 12, 41),
      phase: SessionClipPhase.ready,
      stored: MemoryClip('c1', 1),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReviewPage(clip: clip, playerFactory: () => video, platformFactory: (_) => platform),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  testWidgets('autoplays in a loop, muted', (tester) async {
    await pump(tester);
    expect(video.value.isPlaying, isTrue);
    expect(video.value.isLooping, isTrue);
    expect(video.value.volume, 0);
  });

  testWidgets('next frame pauses, snaps to the frame on screen and steps one frame', (tester) async {
    await pump(tester);
    platform.shown = const Duration(milliseconds: 1010); // Inside frame 30 of the 30 fps grid.
    await tapTooltip(tester, 'Next frame');
    expect(video.value.isPlaying, isFalse);
    expect(platform.awake, isTrue);
    // Snap to frame 30 (1000 ms), then frame 31 (1033.333 ms, floored for ExoPlayer).
    expect(video.seeks, [const Duration(milliseconds: 1000), const Duration(milliseconds: 1033)]);

    await tapTooltip(tester, 'Next frame');
    await tapTooltip(tester, 'Previous frame');
    await tapTooltip(tester, 'Previous frame');
    expect(video.seeks.skip(2), [
      const Duration(milliseconds: 1066),
      const Duration(milliseconds: 1033),
      const Duration(milliseconds: 1000),
    ]);
  });

  testWidgets('steps through the real frame timestamps, centred for the browser', (tester) async {
    // Frames at 0, 33, 67 (a dropped frame) and 134 ms.
    final timeline = FrameTimeline.parse(_clip());
    await pump(tester, timeline: timeline, rule: SeekRule.containing);
    platform.shown = const Duration(milliseconds: 40);
    await tapTooltip(tester, 'Next frame');
    expect(video.seeks, [const Duration(milliseconds: 50), const Duration(milliseconds: 101)]);
    await tapTooltip(tester, 'Next frame');
    await tapTooltip(tester, 'Next frame'); // Last frame: stays.
    expect(video.seeks.skip(2), [const Duration(milliseconds: 151), const Duration(milliseconds: 151)]);
  });

  testWidgets('tap on the video toggles play/pause; play forgets the paused frame', (tester) async {
    await pump(tester);
    platform.shown = const Duration(milliseconds: 500);
    await tester.tap(find.byKey(const ValueKey('review-video')));
    await tester.pumpAndSettle();
    expect(video.value.isPlaying, isFalse);
    await tester.tap(find.byKey(const ValueKey('review-video')));
    await tester.pumpAndSettle();
    expect(video.value.isPlaying, isTrue);
    expect(platform.awake, isFalse);

    platform.shown = const Duration(seconds: 2);
    await tapTooltip(tester, 'Previous frame');
    expect(video.seeks.last, const Duration(milliseconds: 1966));
  });

  testWidgets('horizontal drag scrubs frame by frame and resumes playback', (tester) async {
    await pump(tester);
    platform.shown = Duration.zero;
    final drag = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('review-video'))));
    for (var i = 0; i < 20; i++) {
      await drag.moveBy(const Offset(ReviewPage.dragPixelsPerFrame, 0));
      await tester.pumpAndSettle();
    }
    // The first move is eaten by the drag slop; the rest move one frame each.
    expect(video.value.isPlaying, isFalse);
    expect(video.seeks.last, greaterThan(const Duration(milliseconds: 400)));
    final last = video.seeks.last;
    await drag.up();
    await tester.pumpAndSettle();
    expect(video.value.isPlaying, isTrue);
    expect(video.seeks.last, last);
  });

  testWidgets('speed buttons set the playback rate', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('0.25'));
    await tester.pumpAndSettle();
    expect(video.value.playbackSpeed, 0.25);
  });
}

/// The test fragment of frame_timeline_test.dart: frames at 0, 33, 67 and 134 ms, then 167 ms end.
Uint8List _clip() =>
    _box('moov', [
          ..._box('trak', [
            ..._box('mdia', [
              ..._box('mdhd', [..._u32(0), ..._u32(0), ..._u32(0), ..._u32(90000), ..._u32(0), ..._u32(0)]),
            ]),
          ]),
        ])
        .followedBy(
          _box('moof', [
            ..._box('traf', [
              ..._box('tfhd', [..._u32(0x020000), ..._u32(1)]),
              ..._box('tfdt', [..._u32(0), ..._u32(0)]),
              ..._box('trun', [
                ..._u32(0x100),
                ..._u32(4),
                for (final d in [2970, 3060, 6030, 2970]) ..._u32(d),
              ]),
            ]),
          ]),
        )
        .toUint8List();

List<int> _box(String type, List<int> body) => [..._u32(8 + body.length), ...type.codeUnits, ...body];
List<int> _u32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];

extension on Iterable<int> {
  Uint8List toUint8List() => Uint8List.fromList(toList());
}

/// A 10 s, 30 fps controller without a platform player.
class FakeVideo extends VideoPlayerController {
  FakeVideo() : super.networkUrl(Uri.parse('blob:fake'));

  final seeks = <Duration>[];

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true, duration: const Duration(seconds: 10), size: const Size(1920, 1080));
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> setLooping(bool looping) async => value = value.copyWith(isLooping: looping);

  @override
  Future<void> setVolume(double volume) async => value = value.copyWith(volume: volume);

  @override
  Future<void> setPlaybackSpeed(double speed) async => value = value.copyWith(playbackSpeed: speed);

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<Duration?> get position async => value.position;

}

class FakePlatform implements PlayerPlatform {
  FakePlatform(this.player, this.timeline, this.seekRule);

  final FakeVideo player;
  final FrameTimeline? timeline;
  Duration? shown;
  bool awake = false;

  @override
  final SeekRule seekRule;

  @override
  Future<FrameTimeline?> loadTimeline() async => timeline;

  @override
  Future<Duration?> shownFrameTime() async => shown;

  @override
  void keepAwake(bool on) => awake = on;

  @override
  void dispose() {}
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/player/frame_timeline.dart';
import 'package:instant_replay/features/viewer/player/player_platform.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/review_page.dart';
import 'package:instant_replay/features/viewer/ui/telestrator.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'fakes.dart';

void main() {
  late FakeVideo video;
  late FakePlatform platform;

  Future<void> pump(
    WidgetTester tester, {
    FrameTimeline? timeline,
    SeekRule rule = SeekRule.atOrAfter,
    ReviewPlaylist? playlist,
    Size size = const Size(1280, 800),
    VideoPlayerController Function()? player,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    video = FakeVideo();
    platform = FakePlatform(video, timeline, rule);
    final clip = SessionClip(
      requestId: 'r1',
      seconds: 10,
      requestedAt: DateTime(2026, 10, 30, 12, 41),
      phase: SessionClipPhase.ready,
      stored: MemoryClip('c1', 1),
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReviewPage(
            clip: clip,
            playlist: playlist,
            playerFactory: player ?? () => video,
            platformFactory: (_) => platform,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder speedButton(String label) =>
      find.descendant(of: find.byKey(const ValueKey('review-speed')), matching: find.text(label));

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  testWidgets('the tag picked in review is kept for the clip', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('review-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-${TagsNotifier.bad}')).last);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ReviewPage)));
    expect(container.read(clipTagsProvider), {'r1': TagsNotifier.bad});
    expect(find.text('Bad · 12:41'), findsOneWidget);
  });

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

  testWidgets('speed buttons set the playback rate; the video shows it', (tester) async {
    await pump(tester);
    await tester.tap(speedButton('0.25×'));
    await tester.pumpAndSettle();
    expect(video.value.playbackSpeed, 0.25);
    expect(find.text('0.25×'), findsNWidgets(2));
  });

  testWidgets('the frame counter and the timecode follow the frame on screen', (tester) async {
    await pump(tester);
    platform.shown = const Duration(milliseconds: 1010);
    await tapTooltip(tester, 'Next frame');
    expect(find.text('F 32 / 300'), findsOneWidget);
    expect(find.text('00:01.0'), findsOneWidget);
  });

  testWidgets('the scrubber pauses, shows the frame under the finger and resumes on release', (tester) async {
    await pump(tester);
    platform.shown = Duration.zero;
    final scrubber = find.byKey(const ValueKey('review-scrubber'));
    final rect = tester.getRect(scrubber);
    final drag = await tester.startGesture(rect.centerLeft + const Offset(10, 0));
    await drag.moveTo(rect.center);
    await tester.pumpAndSettle();
    await drag.moveTo(rect.center + Offset(rect.width / 4, 0));
    await tester.pumpAndSettle();
    expect(video.value.isPlaying, isFalse);
    // Three quarters of a 10 s clip.
    expect(video.seeks.last.inMilliseconds, closeTo(7500, 50));
    await drag.up();
    await tester.pumpAndSettle();
    expect(video.value.isPlaying, isTrue);

    // A tap jumps there.
    await tester.tapAt(rect.centerLeft + Offset(rect.width / 4, 0));
    await tester.pumpAndSettle();
    expect(video.seeks.last.inMilliseconds, closeTo(2500, 50));
  });

  testWidgets('a clip that cannot play says so, and Retry tries a new player', (tester) async {
    var attempts = 0;
    await pump(tester, player: () => attempts++ == 0 ? _BrokenVideo() : video);
    expect(find.byKey(const ValueKey('review-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('review-error')), findsNothing);
    expect(video.value.isPlaying, isTrue);
  });

  testWidgets('on a phone, Tag and Export are in the menu', (tester) async {
    await pump(tester, size: const Size(360, 640));
    expect(find.byKey(const ValueKey('review-draw')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-tag')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('review-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-${TagsNotifier.bad}')).last);
    await tester.pumpAndSettle();
    expect(find.text('Bad · 12:41'), findsOneWidget);
  });

  group('fits', () {
    for (final size in const [Size(360, 640), Size(640, 360), Size(800, 416), Size(1280, 800), Size(800, 1280)]) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('$name, playing and drawing, without overflow', (tester) async {
        final log = <String>[];
        await pump(
          tester,
          size: size,
          playlist: ReviewPlaylist(
            index: 1,
            length: 3,
            onPrevious: () => log.add('previous'),
            onNext: () => log.add('next'),
            speed: 1,
            onSpeed: (_) {},
          ),
        );
        expect(tester.takeException(), isNull);
        void inside(Finder f) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(0), reason: '$f');
          expect(r.top, greaterThanOrEqualTo(0), reason: '$f');
          expect(r.right, lessThanOrEqualTo(size.width), reason: '$f');
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$f');
        }

        for (final k in ['review-play', 'review-scrubber', 'review-speed', 'review-next-clip', 'review-draw']) {
          inside(find.byKey(ValueKey(k)));
        }
        inside(find.byTooltip('Next frame'));
        expect(tester.getSize(find.byKey(const ValueKey('review-play'))).height, greaterThanOrEqualTo(48));
        // The video keeps a useful height.
        expect(tester.getSize(find.byKey(const ValueKey('review-video'))).height, greaterThan(150));

        await tester.tap(find.byKey(const ValueKey('review-draw')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final k in ['draw-tool-arrow', 'draw-tool-select', 'draw-tool-eraser', 'draw-color-4', 'draw-thick', 'draw-done']) {
          inside(find.byKey(ValueKey(k)));
          expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
        }
        inside(find.byTooltip('Undo'));
        inside(find.byTooltip('Clear drawing'));
        await tester.tap(find.byKey(const ValueKey('draw-done')));
        await tester.pumpAndSettle();
        expect(find.byType(TelestratorToolbar), findsNothing);
      });
    }
  });

  group('zoom', () {
    /// Two fingers from 40 px apart to 120 px apart about [at] (the zoom counts from where the
    /// pinch got past the slop, so it ends between ×1 and ×3).
    Future<void> pinchOut(WidgetTester tester, Offset at) async {
      final a = await tester.startGesture(at - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(at + const Offset(20, 0), pointer: 2);
      for (var i = 1; i <= 10; i++) {
        await a.moveTo(at - Offset(20 + 4.0 * i, 0));
        await b.moveTo(at + Offset(20 + 4.0 * i, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    double zoom(WidgetTester tester) => double.parse(
      tester
          .widget<Text>(
            find.descendant(of: find.byKey(const ValueKey('review-zoom-reset')), matching: find.byType(Text)),
          )
          .data!
          .substring(1),
    );

    testWidgets('a pinch zooms the playing video without scrubbing; the button resets it', (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('review-zoom-reset')), findsNothing);
      final seeks = video.seeks.length;
      await pinchOut(tester, tester.getCenter(find.byKey(const ValueKey('review-video'))));
      expect(zoom(tester), inInclusiveRange(1.4, 3));
      expect(video.value.isPlaying, isTrue);
      expect(video.seeks, hasLength(seeks));

      await tester.tap(find.byKey(const ValueKey('review-zoom-reset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-zoom-reset')), findsNothing);
    });

    testWidgets('while drawing, a pinch with nothing selected zooms, and draws nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      await pinchOut(tester, tester.getCenter(find.byKey(const ValueKey('review-canvas'))));
      final zoomed = zoom(tester);
      expect(zoomed, inInclusiveRange(1.4, 3));
      final toolbar = tester.widget<TelestratorToolbar>(find.byType(TelestratorToolbar));
      expect(toolbar.controller.isEmpty, isTrue);
      expect(toolbar.controller.canUndo, isFalse);

      // The zoom stays when draw mode ends.
      await tester.tap(find.byKey(const ValueKey('draw-done')));
      await tester.pumpAndSettle();
      expect(zoom(tester), zoomed);
    });
  });

  group('watch all', () {
    ReviewPlaylist playlist(int index, List<String> log, {int length = 3}) => ReviewPlaylist(
      index: index,
      length: length,
      onPrevious: index == 0 ? null : () => log.add('previous'),
      onNext: () => log.add('next'),
      speed: 0.5,
      onSpeed: (s) => log.add('speed $s'),
    );

    void finish() => video.value = video.value.copyWith(isPlaying: false, isCompleted: true);

    testWidgets('plays once at the kept speed and moves on when the clip ends', (tester) async {
      final log = <String>[];
      await pump(tester, playlist: playlist(1, log));
      expect(video.value.isLooping, isFalse);
      expect(video.value.playbackSpeed, 0.5);
      expect(find.textContaining('clip 2 of 3'), findsOneWidget);
      finish();
      await tester.pump();
      finish(); // reported again: still one move
      await tester.pump();
      expect(log, ['next']);

      await tester.tap(find.byKey(const ValueKey('review-prev-clip')));
      await tester.tap(find.byKey(const ValueKey('review-next-clip')));
      await tester.tap(speedButton('0.25×'));
      await tester.pumpAndSettle();
      expect(log, ['next', 'previous', 'next', 'speed 0.25']);
    });

    testWidgets('the last clip stays on its end; its button watches all again', (tester) async {
      final log = <String>[];
      await pump(tester, playlist: playlist(2, log));
      finish();
      await tester.pump();
      expect(log, isEmpty);
      expect(find.byTooltip('Watch all again'), findsOneWidget);
      await tapTooltip(tester, 'Play');
      expect(video.seeks.last, Duration.zero);
      expect(video.value.isPlaying, isTrue);
    });

    testWidgets('a clip on its own loops', (tester) async {
      await pump(tester);
      expect(video.value.isLooping, isTrue);
      expect(find.byKey(const ValueKey('review-next-clip')), findsNothing);
    });
  });

  group('draw mode', () {
    TelestratorController drawing(WidgetTester tester) =>
        (tester.widget(find.byType(TelestratorToolbar)) as TelestratorToolbar).controller;

    Future<void> stroke(WidgetTester tester) async {
      final canvas = find.byKey(const ValueKey('review-canvas'));
      await tester.dragFrom(tester.getCenter(canvas), const Offset(60, 40));
      await tester.pumpAndSettle();
    }

    testWidgets('pauses, draws in the chosen colour, undo and clear', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      expect(video.value.isPlaying, isFalse);
      expect(find.byType(TelestratorToolbar), findsOneWidget);
      expect(find.text('Drawing on'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('draw-tool-pen')));
      await tester.tap(find.byKey(const ValueKey('draw-color-1')));
      await stroke(tester);
      await stroke(tester);
      final c = drawing(tester);
      expect(c.strokes, hasLength(2));
      expect(c.strokes.first.color, TelestratorController.colors[1]);
      // A drag while drawing does not scrub.
      expect(video.value.isPlaying, isFalse);

      await tapTooltip(tester, 'Undo');
      expect(c.strokes, hasLength(1));
      await tapTooltip(tester, 'Clear drawing');
      expect(c.isEmpty, isTrue);
    });

    testWidgets('arrow, circle and line keep two points; thickness and a tap without a drag', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      final c = drawing(tester);
      expect(c.tool, TelestratorTool.arrow);

      await stroke(tester);
      await tester.tap(find.byKey(const ValueKey('draw-tool-circle')));
      await tester.tap(find.byKey(const ValueKey('draw-thick')));
      await stroke(tester);
      await tester.tap(find.byKey(const ValueKey('draw-tool-line')));
      await stroke(tester);
      await tester.pump();
      expect([for (final s in c.strokes) s.tool], [TelestratorTool.arrow, TelestratorTool.circle, TelestratorTool.line]);
      expect([for (final s in c.strokes) s.points.length], [2, 2, 2]);
      expect([for (final s in c.strokes) s.thick], [false, true, true]);

      // A shape needs a drag: a tap leaves nothing behind.
      await tester.tap(find.byKey(const ValueKey('review-canvas')));
      await tester.pumpAndSettle();
      expect(c.strokes, hasLength(3));
    });

    testWidgets('select a mark, move it, recolour it, delete it; Undo takes each back', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      final c = drawing(tester);
      final canvas = find.byKey(const ValueKey('review-canvas'));
      final width = tester.getSize(canvas).width;
      final onArrow = tester.getCenter(canvas) + const Offset(30, 20);
      await stroke(tester);
      final start = c.strokes.single.points.first;

      await tester.tap(find.byKey(const ValueKey('draw-tool-select')));
      await tester.tapAt(onArrow);
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(c.selected, same(c.strokes.single));
      expect(find.byKey(const ValueKey('draw-delete')), findsOneWidget);

      await tester.dragFrom(onArrow, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(c.strokes.single.points.first.dx, greaterThan(start.dx + 50 / width));
      await tapTooltip(tester, 'Undo');
      expect(c.strokes.single.points.first, start);

      await tester.tapAt(onArrow);
      await tester.pumpAndSettle(kDoubleTapTimeout);
      await tester.tap(find.byKey(const ValueKey('draw-color-3')));
      await tester.pump();
      expect(c.strokes.single.color, TelestratorController.colors[3]);
      await tester.tap(find.byKey(const ValueKey('draw-delete')));
      await tester.pump();
      expect(c.isEmpty, isTrue);
      expect(find.byKey(const ValueKey('draw-delete')), findsNothing);
      await tapTooltip(tester, 'Undo');
      expect(c.strokes.single.color, TelestratorController.colors[3]);

      // A tap away from every mark selects nothing.
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(10, 10));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(c.selected, isNull);
    });

    testWidgets('a double tap removes a mark with any tool; the eraser removes what it touches', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      final c = drawing(tester);
      final center = tester.getCenter(find.byKey(const ValueKey('review-canvas')));
      await tester.dragFrom(center, const Offset(80, 0));
      await tester.dragFrom(center + const Offset(0, 100), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(c.strokes, hasLength(2));

      Future<void> doubleTap(Offset at) async {
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(at);
        await tester.pumpAndSettle();
      }

      await doubleTap(center + const Offset(40, 0));
      expect(c.strokes, hasLength(1));
      expect(c.strokes.single.points.first.dy, greaterThan(0.5));
      // Away from the marks a double tap does nothing.
      await doubleTap(center + const Offset(40, -100));
      expect(c.strokes, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('draw-tool-eraser')));
      await tester.dragFrom(center + const Offset(40, 60), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      // An eraser drag adds nothing, and Undo brings back what it removed.
      await tapTooltip(tester, 'Undo');
      expect(c.strokes, hasLength(1));
      await tapTooltip(tester, 'Undo');
      expect(c.strokes, hasLength(2));
    });

    testWidgets('a pinch scales and turns the selected mark; handles move an end or a corner', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      final c = drawing(tester);
      final canvas = find.byKey(const ValueKey('review-canvas'));
      final size = tester.getSize(canvas);
      final center = tester.getCenter(canvas);
      Offset px(Offset rel) => Offset(rel.dx * size.width, rel.dy * size.height);

      // A horizontal arrow, 100 px long, from the centre.
      await tester.dragFrom(center, const Offset(100, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draw-tool-select')));
      await tester.tapAt(center + const Offset(50, 0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(c.selected, isNotNull);

      // Fingers 40 px apart turn a quarter clockwise and end 80 px apart.
      final mid = center + const Offset(50, 0);
      final a = await tester.startGesture(mid - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(mid + const Offset(20, 0), pointer: 2);
      for (var i = 1; i <= 10; i++) {
        final t = i / 10, angle = t * math.pi / 2, r = 20 + 20 * t;
        final v = Offset(math.cos(angle), math.sin(angle)) * r;
        await a.moveTo(mid - v);
        await b.moveTo(mid + v);
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final arrow = c.strokes.single;
      final d = px(arrow.points.last) - px(arrow.points.first);
      expect(d.distance, greaterThan(130));
      expect(math.atan2(d.dy, d.dx), greaterThan(math.pi / 4)); // Turned clockwise, towards down.
      expect(arrow.points.length, 2);
      await tapTooltip(tester, 'Undo');
      expect(px(c.strokes.single.points.last) - px(c.strokes.single.points.first), const Offset(100, 0));

      // The arrow's tip handle: only the tip moves.
      await tester.tapAt(center + const Offset(50, 0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      await tester.dragFrom(center + const Offset(100, 0), const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(px(c.strokes.single.points.first), offsetMoreOrLessEquals(center - tester.getTopLeft(canvas)));
      expect(px(c.strokes.single.points.last), offsetMoreOrLessEquals(center - tester.getTopLeft(canvas) + const Offset(100, 60)));

      // A circle's corner handle: the opposite corner stays.
      await tester.tap(find.byKey(const ValueKey('draw-tool-circle')));
      await tester.dragFrom(center - const Offset(150, 100), const Offset(60, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draw-tool-select')));
      await tester.tapAt(center - const Offset(120, 100));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(c.selected?.tool, TelestratorTool.circle);
      await tester.dragFrom(center - const Offset(90, 60), const Offset(40, 20));
      await tester.pumpAndSettle();
      final circle = c.strokes.last;
      final origin = center - tester.getTopLeft(canvas);
      expect(px(circle.points.first), offsetMoreOrLessEquals(origin - const Offset(150, 100)));
      expect(px(circle.points.last), offsetMoreOrLessEquals(origin - const Offset(50, 40)));
    });

    testWidgets('play leaves draw mode and drops the drawing', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      await stroke(tester);
      await tapTooltip(tester, 'Play');
      expect(video.value.isPlaying, isTrue);
      expect(find.byType(TelestratorToolbar), findsNothing);
      expect(find.byKey(const ValueKey('review-canvas')), findsNothing);
    });

    testWidgets('a frame step leaves draw mode; Done keeps the video paused', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      await tapTooltip(tester, 'Next frame');
      expect(find.byType(TelestratorToolbar), findsNothing);

      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draw-done')));
      await tester.pumpAndSettle();
      expect(find.byType(TelestratorToolbar), findsNothing);
      expect(video.value.isPlaying, isFalse);
    });
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

/// A clip the player cannot open.
class _BrokenVideo extends FakeVideo {
  @override
  Future<void> initialize() async => throw Exception('no codec');
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

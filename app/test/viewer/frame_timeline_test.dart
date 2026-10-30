import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/viewer/player/frame_timeline.dart';

const timescale = 90000;

void main() {
  group('FrameTimeline.parse', () {
    test('reads the frames of a Camera clip (init + sidx + fragments)', () {
      // Two 1 s fragments of 30 frames, 3000 ticks each, as Fmp4.kt writes them.
      final timeline = FrameTimeline.parse(clip([List.filled(30, 3000), List.filled(30, 3000)]));
      expect(timeline.length, 60);
      expect(timeline.start(0), Duration.zero);
      expect(timeline.start(1), const Duration(microseconds: 33333));
      expect(timeline.start(30), const Duration(seconds: 1));
      expect(timeline.duration, const Duration(seconds: 2));
    });

    test('keeps camera jitter and dropped frames', () {
      // 33 ms, 34 ms, a dropped frame (67 ms), 33 ms.
      final timeline = FrameTimeline.parse(
        clip([
          [2970, 3060, 6030, 2970],
        ]),
      );
      expect(timeline.length, 4);
      expect([for (var i = 0; i < 4; i++) timeline.start(i).inMicroseconds], [0, 33000, 67000, 134000]);
      expect(timeline.duration, const Duration(microseconds: 167000));
    });

    test('uses tfdt as the fragment start', () {
      final timeline = FrameTimeline.parse(
        clip([
          [3000, 3000],
          [3000],
        ], gapTicks: 9000),
      );
      expect(timeline.start(2), const Duration(microseconds: 166667));
    });

    test('uses the trex default duration when trun has none', () {
      final timeline = FrameTimeline.parse(clip([List.filled(3, 3000)], perSampleDuration: false));
      expect(timeline.start(2), const Duration(microseconds: 66667));
    });

    test('orders frames by presentation time (composition offsets)', () {
      final bytes = clip(
        [
          [3000, 3000, 3000],
        ],
        offsets: [3000, 3000, -6000],
      );
      final timeline = FrameTimeline.parse(bytes);
      expect([for (var i = 0; i < 3; i++) timeline.start(i).inMicroseconds], [0, 33333, 66667]);
    });

    test('rejects a file without samples', () {
      expect(() => FrameTimeline.parse(Uint8List.fromList(box('ftyp', [0, 0, 0, 0]))), throwsFormatException);
      expect(() => FrameTimeline.parse(Uint8List(3)), throwsFormatException);
    });

    test('parses only the index boxes as well as the whole file', () {
      final full = FrameTimeline.parse(clip([List.filled(5, 3000)]));
      final indexOnly = FrameTimeline.parse(clip([List.filled(5, 3000)], withMdat: false));
      expect(indexOnly.length, full.length);
      expect(indexOnly.duration, full.duration);
    });
  });

  group('frame math', () {
    final grid = FrameTimeline.uniform(const Duration(seconds: 10));

    test('uniform grid is 30 fps', () {
      expect(grid.length, 300);
      expect(grid.start(299), const Duration(microseconds: 9966666));
      expect(FrameTimeline.uniform(Duration.zero).length, 1);
    });

    test('indexAt finds the frame on screen', () {
      expect(grid.indexAt(Duration.zero), 0);
      expect(grid.indexAt(const Duration(microseconds: 33332)), 0);
      expect(grid.indexAt(const Duration(microseconds: 33333)), 1);
      expect(grid.indexAt(const Duration(seconds: 1)), 30);
      expect(grid.indexAt(const Duration(seconds: -1)), 0);
      expect(grid.indexAt(const Duration(seconds: 99)), 299);
    });

    test('step stays inside the clip', () {
      expect(grid.step(10, 1), 11);
      expect(grid.step(10, -1), 9);
      expect(grid.step(0, -1), 0);
      expect(grid.step(299, 1), 299);
      expect(grid.step(5, 1000), 299);
    });

    // Each player must land on exactly the frame asked for, from every frame of the clip.
    for (final rule in SeekRule.values) {
      test('seekTarget lands on every frame ($rule)', () {
        final jittery = FrameTimeline.parse(
          clip([
            for (var f = 0; f < 10; f++) [for (var i = 0; i < 30; i++) i % 7 == 3 ? 6030 : 2970 + (i % 3) * 45],
          ]),
        );
        for (final timeline in [grid, jittery]) {
          for (var i = 0; i < timeline.length; i++) {
            final target = timeline.seekTarget(i, rule);
            expect(target.inMicroseconds % 1000, 0, reason: 'players seek in whole ms');
            expect(shownAfterSeek(timeline, target, rule), i, reason: 'frame $i via $target');
          }
        }
      });
    }

    test('stepping ±1 from any frame shows the neighbour', () {
      for (final rule in SeekRule.values) {
        var frame = 0;
        for (var n = 0; n < 299; n++) {
          final next = grid.step(frame, 1);
          expect(shownAfterSeek(grid, grid.seekTarget(next, rule), rule), frame + 1);
          frame = next;
        }
        for (var n = 0; n < 299; n++) {
          final prev = grid.step(frame, -1);
          expect(shownAfterSeek(grid, grid.seekTarget(prev, rule), rule), frame - 1);
          frame = prev;
        }
      }
    });
  });
}

/// The frame a player following [rule] shows after seeking to [t].
int shownAfterSeek(FrameTimeline timeline, Duration t, SeekRule rule) => switch (rule) {
  SeekRule.containing => timeline.indexAt(t),
  SeekRule.atOrAfter => [
    for (var i = 0; i < timeline.length; i++)
      if (timeline.start(i) >= t) i,
  ].first,
};

/// A clip laid out like the Camera's (Fmp4.kt): ftyp, moov, sidx, then moof+mdat per fragment.
Uint8List clip(
  List<List<int>> fragments, {
  int gapTicks = 0,
  bool perSampleDuration = true,
  List<int>? offsets,
  bool withMdat = true,
}) {
  final out = <int>[
    ...box('ftyp', [...ascii('isom'), ...u32(0x200), ...ascii('isom')]),
    ...box('moov', [
      ...box('mvhd', [...u32(0), ...List.filled(96, 0)]),
      ...box('trak', [
        ...box('tkhd', [...u32(3), ...List.filled(80, 0)]),
        ...box('mdia', [
          ...box('mdhd', [...u32(0), ...u32(0), ...u32(0), ...u32(timescale), ...u32(0), ...u32(0)]),
        ]),
      ]),
      ...box('mvex', [
        ...box('trex', [...u32(0), ...u32(1), ...u32(1), ...u32(3000), ...u32(0), ...u32(0)]),
      ]),
    ]),
    ...box('sidx', [...u32(0), ...List.filled(20, 0)]),
  ];
  var decode = 0;
  for (final (seq, durations) in fragments.indexed) {
    final flags = 0x001 | (perSampleDuration ? 0x100 : 0) | 0x200 | 0x400 | (offsets != null ? 0x800 : 0);
    out.addAll(
      box('moof', [
        ...box('mfhd', [...u32(0), ...u32(seq + 1)]),
        ...box('traf', [
          ...box('tfhd', [...u32(0x020000), ...u32(1)]),
          ...box('tfdt', [...u32(0x01000000), ...u64(decode)]),
          ...box('trun', [
            ...u32((offsets != null ? 0x01000000 : 0) | flags),
            ...u32(durations.length),
            ...u32(0),
            for (final (i, d) in durations.indexed) ...[
              if (perSampleDuration) ...u32(d),
              ...u32(4),
              ...u32(0),
              if (offsets != null) ...u32(offsets[i] & 0xFFFFFFFF),
            ],
          ]),
        ]),
      ]),
    );
    if (withMdat) out.addAll(box('mdat', List.filled(4 * durations.length, 0xAB)));
    decode += durations.fold(0, (a, b) => a + b) + gapTicks;
  }
  return Uint8List.fromList(out);
}

List<int> box(String type, List<int> body) => [...u32(8 + body.length), ...ascii(type), ...body];
List<int> ascii(String s) => s.codeUnits;
List<int> u32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];
List<int> u64(int v) => [...u32(v >> 32), ...u32(v & 0xFFFFFFFF)];

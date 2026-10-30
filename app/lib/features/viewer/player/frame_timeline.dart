import 'dart:typed_data';

/// How a player picks the frame to show after a seek to time `t`.
enum SeekRule {
  /// The frame whose display interval contains `t` (HTML `<video>`).
  containing,

  /// The first frame whose timestamp is at or after `t` (ExoPlayer with exact seeks, the
  /// `video_player` default on Android).
  atOrAfter,
}

/// The presentation timestamps of every frame of a clip, for exact frame stepping (SPEC §5.5).
///
/// Built from the clip's fMP4 boxes ([FrameTimeline.parse]), so camera jitter and dropped frames
/// are accounted for; [FrameTimeline.uniform] is the fallback when the file can't be read.
class FrameTimeline {
  FrameTimeline._(this._startsUs, this._endUs);

  /// Frames of [duration] on a fixed grid of [fps].
  factory FrameTimeline.uniform(Duration duration, {int fps = 30}) {
    final total = duration.inMicroseconds;
    final count = total <= 0 ? 1 : (total * fps / Duration.microsecondsPerSecond).ceil();
    return FrameTimeline._([
      for (var i = 0; i < count; i++) i * Duration.microsecondsPerSecond ~/ fps,
    ], total <= 0 ? Duration.microsecondsPerSecond ~/ fps : total);
  }

  /// Reads `moov` (track timescale, `trex` defaults) and every `moof` (`tfhd`, `tfdt`, `trun`)
  /// of a single-video-track (f)MP4. Any other top-level box is skipped, so the input may be the
  /// whole file or just its non-`mdat` boxes. Throws [FormatException] if there are no samples.
  factory FrameTimeline.parse(Uint8List mp4) {
    final data = ByteData.sublistView(mp4);
    var timescale = 0;
    var trexDuration = 0;
    final samples = <(int, int)>[]; // (presentation time, duration) in timescale units.
    for (final box in _boxes(data, 0, data.lengthInBytes)) {
      if (box.type == 'moov') {
        for (final b in _walk(data, box, const {'trak', 'mdia', 'mvex'})) {
          if (b.type == 'mdhd') {
            final version = data.getUint8(b.body);
            timescale = data.getUint32(b.body + (version == 1 ? 20 : 12));
          } else if (b.type == 'trex') {
            trexDuration = data.getUint32(b.body + 12);
          }
        }
      } else if (box.type == 'moof') {
        for (final traf in _boxes(data, box.body, box.end).where((b) => b.type == 'traf')) {
          _readTraf(data, traf, trexDuration, samples);
        }
      }
    }
    if (timescale == 0 || samples.isEmpty) throw const FormatException('No video samples in the MP4');
    samples.sort((a, b) => a.$1.compareTo(b.$1));
    int us(int ticks) => (ticks * Duration.microsecondsPerSecond / timescale).round();
    final last = samples.last;
    return FrameTimeline._([for (final s in samples) us(s.$1)], us(last.$1 + last.$2));
  }

  /// Ascending start time of each frame, in microseconds.
  final List<int> _startsUs;

  /// When the last frame stops being shown, in microseconds.
  final int _endUs;

  int get length => _startsUs.length;

  Duration get duration => Duration(microseconds: _endUs);

  Duration start(int frame) => Duration(microseconds: _startsUs[frame]);

  /// The frame shown at [position]: the last one starting at or before it.
  int indexAt(Duration position) {
    final t = position.inMicroseconds;
    var lo = 0;
    var hi = _startsUs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_startsUs[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// [frame] moved by [delta] frames, kept inside the clip.
  int step(int frame, int delta) => (frame + delta).clamp(0, length - 1);

  /// A whole-millisecond position (players seek in ms) that makes a player following [rule] show
  /// exactly [frame].
  Duration seekTarget(int frame, SeekRule rule) {
    final startUs = _startsUs[frame];
    final ms = switch (rule) {
      // Floor stays inside (previous frame, this frame], as long as frames last over 1 ms.
      SeekRule.atOrAfter => startUs ~/ 1000,
      // The middle is the safest point against rounding in the browser.
      SeekRule.containing => ((startUs + _endOf(frame)) / 2000).round(),
    };
    return Duration(milliseconds: ms);
  }

  int _endOf(int frame) => frame + 1 < length ? _startsUs[frame + 1] : _endUs;

  static void _readTraf(ByteData data, _Box traf, int trexDuration, List<(int, int)> samples) {
    var defaultDuration = trexDuration;
    var decodeTime = 0;
    final runs = <_Box>[];
    for (final b in _boxes(data, traf.body, traf.end)) {
      switch (b.type) {
        case 'tfhd':
          final flags = data.getUint32(b.body) & 0xFFFFFF;
          var at = b.body + 8; // version/flags, track_ID
          if (flags & 0x01 != 0) at += 8; // base-data-offset
          if (flags & 0x02 != 0) at += 4; // sample-description-index
          if (flags & 0x08 != 0) defaultDuration = data.getUint32(at);
        case 'tfdt':
          decodeTime = data.getUint8(b.body) == 1 ? data.getUint64(b.body + 4) : data.getUint32(b.body + 4);
        case 'trun':
          runs.add(b);
      }
    }
    for (final run in runs) {
      final version = data.getUint8(run.body);
      final flags = data.getUint32(run.body) & 0xFFFFFF;
      final count = data.getUint32(run.body + 4);
      var at = run.body + 8;
      if (flags & 0x01 != 0) at += 4; // data-offset
      if (flags & 0x04 != 0) at += 4; // first-sample-flags
      for (var i = 0; i < count; i++) {
        var duration = defaultDuration;
        var offset = 0;
        if (flags & 0x100 != 0) {
          duration = data.getUint32(at);
          at += 4;
        }
        if (flags & 0x200 != 0) at += 4; // size
        if (flags & 0x400 != 0) at += 4; // flags
        if (flags & 0x800 != 0) {
          offset = version == 0 ? data.getUint32(at) : data.getInt32(at);
          at += 4;
        }
        samples.add((decodeTime + offset, duration));
        decodeTime += duration;
      }
    }
  }

  /// The boxes inside [box], descending into [containers].
  static Iterable<_Box> _walk(ByteData data, _Box box, Set<String> containers) sync* {
    for (final b in _boxes(data, box.body, box.end)) {
      yield b;
      if (containers.contains(b.type)) yield* _walk(data, b, containers);
    }
  }

  static Iterable<_Box> _boxes(ByteData data, int from, int to) sync* {
    var at = from;
    while (at + 8 <= to) {
      var size = data.getUint32(at);
      final type = String.fromCharCodes(Uint8List.sublistView(data, at + 4, at + 8));
      var header = 8;
      if (size == 1) {
        if (at + 16 > to) return;
        size = data.getUint64(at + 8);
        header = 16;
      } else if (size == 0) {
        size = to - at;
      }
      if (size < header || at + size > to) return; // Truncated: keep what was read.
      yield _Box(type, at + header, at + size);
      at += size;
    }
  }
}

class _Box {
  const _Box(this.type, this.body, this.end);
  final String type;
  final int body;
  final int end;
}

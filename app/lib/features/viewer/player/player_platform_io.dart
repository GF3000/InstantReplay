import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'frame_timeline.dart';
import 'player_platform.dart';

PlayerPlatform createPlayerPlatform(VideoPlayerController player) => _IoPlayerPlatform(player);

/// Android: ExoPlayer seeks exactly and reports the position of the frame it stopped on.
/// [keepAwake] is a no-op: the native Viewer has no keep-screen-on yet (the screen timeout applies).
class _IoPlayerPlatform implements PlayerPlatform {
  _IoPlayerPlatform(this.player);

  final VideoPlayerController player;

  @override
  SeekRule get seekRule => SeekRule.atOrAfter;

  @override
  Future<FrameTimeline?> loadTimeline() async {
    if (player.dataSourceType != DataSourceType.file) return null;
    try {
      return parseTimeline(await _readIndexBoxes(File(Uri.parse(player.dataSource).toFilePath())));
    } on Object {
      return null;
    }
  }

  @override
  Future<Duration?> shownFrameTime() => player.position;

  @override
  void keepAwake(bool on) {}

  @override
  void dispose() {}

  /// The top-level boxes of [file] except `mdat`, which holds the frames and almost all the bytes.
  static Future<Uint8List> _readIndexBoxes(File file) async {
    final raf = await file.open();
    try {
      final out = BytesBuilder(copy: false);
      final length = await raf.length();
      var at = 0;
      while (at + 8 <= length) {
        await raf.setPosition(at);
        final header = ByteData.sublistView(await raf.read(16));
        var size = header.getUint32(0);
        final type = String.fromCharCodes(Uint8List.sublistView(header, 4, 8));
        if (size == 1 && header.lengthInBytes == 16) size = header.getUint64(8);
        if (size == 0) size = length - at;
        if (size < 8 || at + size > length) break;
        if (type != 'mdat') {
          await raf.setPosition(at);
          out.add(await raf.read(size));
        }
        at += size;
      }
      return out.takeBytes();
    } finally {
      await raf.close();
    }
  }
}

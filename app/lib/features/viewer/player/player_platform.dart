import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'frame_timeline.dart';
import 'player_platform_io.dart' if (dart.library.js_interop) 'player_platform_web.dart' as platform;

/// What the review screen needs from the platform beyond `video_player` (SPEC §5.5, §6).
abstract class PlayerPlatform {
  /// The platform helper for [player], which must be created by [StoredClip.createPlayer].
  factory PlayerPlatform(VideoPlayerController player) => platform.createPlayerPlatform(player);

  /// How the platform player picks a frame after a seek.
  SeekRule get seekRule;

  /// The clip's frame timestamps, read from the file or blob behind [VideoPlayerController.dataSource];
  /// null when it can't be read or parsed.
  Future<FrameTimeline?> loadTimeline();

  /// The timestamp of the frame on screen, or null if unknown. Call after the player is paused.
  Future<Duration?> shownFrameTime();

  /// Keeps the screen on while [on]; the review screen turns it on while paused.
  void keepAwake(bool on);

  void dispose();
}

/// [FrameTimeline.parse], or null for a file it doesn't understand.
FrameTimeline? parseTimeline(Uint8List bytes) {
  try {
    return FrameTimeline.parse(bytes);
  } on Object {
    return null;
  }
}

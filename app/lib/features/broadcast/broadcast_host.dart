import 'package:replay_protocol/replay_protocol.dart';

/// What the Camera's API server needs from broadcast mode (SPEC §12): the scoreboard and the
/// YouTube stream, both owned by the Camera screen. Keeps the server free of Riverpod.
abstract interface class BroadcastHost {
  /// Capture runs in broadcast mode: `status` carries [scoreboard] and [info], and the commands
  /// below are accepted. False in replay mode.
  bool get active;

  /// The scoreboard as of now (a running clock anchored at this moment).
  ScoreboardState get scoreboard;

  /// The stream as viewers see it (never the key).
  BroadcastInfo get info;

  /// After every scoreboard change, stream state or configuration change and mode switch, so the
  /// server can push a status at once. Not for the bitrate and uptime ticks (they ride on stats).
  Stream<void> get changes;

  void scoreboardCommand(ScoreboardCommand command);

  /// [key] null (or empty) keeps the stored key.
  Future<void> configure({required String server, String? key, required int targetKbps, required bool audio});

  /// Throws [BroadcastException] (`not_configured`, `broadcast_failed`). Returns false when the
  /// stream started without the microphone because its permission was denied.
  Future<bool> start();

  Future<void> stop();

  // Replays on air (SPEC §12.6). [changes] fires when one starts, changes speed or ends.

  /// The replay on air, its position as of now; null while the program shows the camera.
  ReplayInfo? get replay;

  /// A replay that failed on air, with the reason.
  Stream<String> get replayFailures;

  /// Puts [clipId] on air at [speed], replacing any replay on air. Throws [BroadcastException]
  /// `not_live` (no stream active), `replay_unavailable` (clip not on the Camera) or
  /// `replay_failed`.
  Future<void> replayAir(String clipId, double speed);

  /// Changes the speed of the replay on air; nothing without one.
  Future<void> replaySpeed(double speed);

  /// Back to the live picture.
  Future<void> replayStop();
}

/// A broadcast command refused with an API error code (`not_configured`, `broadcast_failed`,
/// `mic_permission`, `not_broadcast_mode`, `not_live`, `replay_unavailable`, `replay_failed`).
class BroadcastException implements Exception {
  const BroadcastException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

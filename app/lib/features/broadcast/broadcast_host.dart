import 'package:flutter/foundation.dart' show ValueListenable;
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

  /// The stream microphone's level in dBFS (muted or not); null without an open microphone.
  /// Polled only while something listens, so listen only while viewers need it.
  ValueListenable<double?> get micLevel;

  /// [key] null (or empty) keeps the stored key.
  /// [replayScoreboard] null keeps the stored choice.
  Future<void> configure({
    required String server,
    String? key,
    required int targetKbps,
    required bool audio,
    bool? replayScoreboard,
  });

  /// Throws [BroadcastException] (`not_configured`, `broadcast_failed`, and `youtube_<code>` when
  /// the YouTube account could not prepare its live). Returns false when the stream started
  /// without the microphone because its permission was denied. In YouTube account mode it first
  /// makes sure a live is there and streams to the account's key, as the Camera's own Go live.
  Future<bool> start();

  // YouTube through the Camera (SPEC §12.1). [changes] fires when [youtube] changes.

  /// The Camera's YouTube state for `status.youtube`; null when this Camera has no account
  /// support.
  YouTubeStatus? get youtube;

  /// Runs a viewer's YouTube command with the Camera's account. Returns the ingest server the
  /// stream now goes to (`save`, `create`, `prepare`). Throws [BroadcastException]
  /// `youtube_<code>` (see [YouTubeResult.errorCode]).
  Future<String?> youtubeCommand(YouTubeCmd command);

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
/// `mic_permission`, `not_broadcast_mode`, `not_live`, `replay_unavailable`, `replay_failed`,
/// and `youtube_<code>` for the Camera's YouTube account, e.g. `youtube_quota`).
class BroadcastException implements Exception {
  const BroadcastException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

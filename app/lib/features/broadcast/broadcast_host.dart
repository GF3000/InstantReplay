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
}

/// A broadcast command refused with an API error code (`not_configured`, `broadcast_failed`,
/// `mic_permission`, `not_broadcast_mode`).
class BroadcastException implements Exception {
  const BroadcastException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

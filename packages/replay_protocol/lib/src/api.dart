/// REST routes and auth conventions of API v1 (SPEC §4.1).
///
/// Every route except [pair] and the static web bundle needs the session token, sent as
/// `Authorization: Bearer <token>` or, where headers are impossible (WebSocket in browsers,
/// `<video src>`), as the query parameter [tokenParam].
abstract final class Api {
  static const prefix = '/api/v1';

  /// POST [PairRequest] → [PairResponse]. Rate-limited.
  static const pair = '$prefix/pair';

  /// GET → [CameraInfo].
  static const info = '$prefix/info';

  /// POST [SaveClipRequest] → 202 [ClipDto] (state `recording`; `ready` arrives over WebSocket).
  /// GET → list of [ClipDto] in the outbox.
  static const clips = '$prefix/clips';

  /// GET → the fMP4 file (Range supported).
  static String clip(String id) => '$clips/$id';

  /// POST [AckRequest] → 204, or 409 if the hash does not match.
  static String ack(String id) => '$clips/$id/ack';

  /// WebSocket: signaling, events and keep-alive ([WsMessage]).
  static const ws = '$prefix/ws';

  static const tokenParam = 'k';

  /// Scheme of the token header value.
  static const bearer = 'Bearer';
}

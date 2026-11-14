/// WebSocket messages of API v1: JSON objects `{"type": ..., ...fields}` (SPEC §4.2).
///
/// Live view signaling uses trickle ICE: the Camera sends its offer right away and both sides
/// exchange candidates as they are found, so a slow or empty gathering never blocks the call.
library;

import 'dart:convert';

import 'broadcast.dart';
import 'models.dart';
import 'youtube.dart';

sealed class WsMessage {
  const WsMessage();

  String get type;

  Json fields();

  Json toJson() => {'type': type, ...fields()};

  String encode() => jsonEncode(toJson());

  /// Returns null for unknown types, so newer peers can add messages without breaking older ones.
  static WsMessage? decode(String raw) {
    final j = jsonDecode(raw) as Json;
    return switch (j['type']) {
      Hello.typeName => Hello(protocolVersion: j['protocolVersion']! as int, viewerId: j['viewerId']! as String),
      Welcome.typeName => Welcome(camera: CameraInfo.fromJson(j['camera']! as Json)),
      LiveStart.typeName => LiveStart(codec: j['codec'] as String? ?? 'H264'),
      LiveStop.typeName => const LiveStop(),
      RtcOffer.typeName => RtcOffer(sdp: j['sdp']! as String),
      RtcAnswer.typeName => RtcAnswer(sdp: j['sdp']! as String),
      RtcIce.typeName => RtcIce(
          candidate: j['candidate']! as String,
          sdpMid: j['sdpMid'] as String?,
          sdpMLineIndex: j['sdpMLineIndex'] as int?,
        ),
      ClipChanged.typeName => ClipChanged(clip: ClipDto.fromJson(j['clip']! as Json)),
      StatusUpdate.typeName => StatusUpdate(status: CameraStatus.fromJson(j['status']! as Json)),
      ErrorMessage.typeName => ErrorMessage(code: j['code']! as String, message: j['message'] as String?),
      RecStart.typeName => RecStart(includeSeconds: j['includeSeconds'] as int? ?? 0),
      RecPause.typeName => const RecPause(),
      RecStop.typeName => const RecStop(),
      RecordingFinished.typeName => RecordingFinished(
          name: j['name']! as String,
          parts: j['parts']! as int,
          durationMs: j['durationMs']! as int,
          reason: RecordingEndReason.values.asNameMap()[j['reason']] ?? RecordingEndReason.user,
        ),
      ScoreboardCmd.typeName => switch (ScoreboardCommand.fromJson(j)) {
          final c? => ScoreboardCmd(c),
          null => null,
        },
      BroadcastConfigure.typeName => BroadcastConfigure(
          server: j['server'] as String? ?? BroadcastInfo.defaultServer,
          key: j['key'] as String?,
          targetKbps: j['targetKbps'] as int? ?? BroadcastInfo.defaultKbps,
          audio: j['audio'] as bool? ?? true,
          replayScoreboard: j['replayScoreboard'] as bool?,
        ),
      BroadcastStart.typeName => const BroadcastStart(),
      BroadcastStop.typeName => const BroadcastStop(),
      CameraZoom.typeName => CameraZoom(ratio: (j['ratio']! as num).toDouble()),
      ClipReserve.typeName => ClipReserve(size: j['size']! as int),
      ReplayAir.typeName => ReplayAir(clipId: j['clipId']! as String, speed: (j['speed'] as num? ?? 1).toDouble()),
      ReplaySpeed.typeName => ReplaySpeed(speed: (j['speed']! as num).toDouble()),
      ReplayStop.typeName => const ReplayStop(),
      MicLevel.typeName => MicLevel(db: (j['db'] as num?)?.toDouble()),
      YouTubeCmd.typeName => switch (YouTubeAction.parse(j['action'])) {
          final a? => YouTubeCmd(
              requestId: j['requestId'] as String? ?? '',
              action: a,
              title: j['title'] as String?,
              description: j['description'] as String?,
              privacy: j['privacy'] as String?,
            ),
          null => null, // A newer viewer's action.
        },
      YouTubeResult.typeName => YouTubeResult(
          requestId: j['requestId'] as String? ?? '',
          status: switch (j['status']) {
            final Json y => YouTubeStatus.fromJson(y),
            _ => null,
          },
          server: j['server'] as String?,
          errorCode: j['errorCode'] as String?,
          errorMessage: j['errorMessage'] as String?,
        ),
      Ping.typeName => const Ping(),
      Pong.typeName => const Pong(),
      _ => null,
    };
  }
}

/// Viewer → Camera, first message after connecting.
final class Hello extends WsMessage {
  const Hello({required this.protocolVersion, required this.viewerId});

  static const typeName = 'hello';
  final int protocolVersion;

  /// Stable per viewer install; used for clip ownership (D9) and live sessions.
  final String viewerId;

  @override
  String get type => typeName;

  @override
  Json fields() => {'protocolVersion': protocolVersion, 'viewerId': viewerId};
}

/// Camera → Viewer, reply to [Hello].
final class Welcome extends WsMessage {
  const Welcome({required this.camera});

  static const typeName = 'welcome';
  final CameraInfo camera;

  @override
  String get type => typeName;

  @override
  Json fields() => {'camera': camera.toJson()};
}

/// Viewer → Camera: start the live view. The Camera answers with [RtcOffer].
final class LiveStart extends WsMessage {
  const LiveStart({this.codec = 'H264'});

  static const typeName = 'live_start';
  final String codec;

  @override
  String get type => typeName;

  @override
  Json fields() => {'codec': codec};
}

/// Viewer → Camera: stop the live view.
final class LiveStop extends WsMessage {
  const LiveStop();

  static const typeName = 'live_stop';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

/// Camera → Viewer.
final class RtcOffer extends WsMessage {
  const RtcOffer({required this.sdp});

  static const typeName = 'rtc_offer';
  final String sdp;

  @override
  String get type => typeName;

  @override
  Json fields() => {'sdp': sdp};
}

/// Viewer → Camera.
final class RtcAnswer extends WsMessage {
  const RtcAnswer({required this.sdp});

  static const typeName = 'rtc_answer';
  final String sdp;

  @override
  String get type => typeName;

  @override
  Json fields() => {'sdp': sdp};
}

/// Both directions: one trickled ICE candidate.
final class RtcIce extends WsMessage {
  const RtcIce({required this.candidate, this.sdpMid, this.sdpMLineIndex});

  static const typeName = 'rtc_ice';
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  @override
  String get type => typeName;

  @override
  Json fields() => {
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };
}

/// Camera → all viewers: any outbox change. The requester downloads and acks `ready` clips.
final class ClipChanged extends WsMessage {
  const ClipChanged({required this.clip});

  static const typeName = 'clip_changed';
  final ClipDto clip;

  @override
  String get type => typeName;

  @override
  Json fields() => {'clip': clip.toJson()};
}

/// Camera → all viewers, about once per second.
final class StatusUpdate extends WsMessage {
  const StatusUpdate({required this.status});

  static const typeName = 'status';
  final CameraStatus status;

  @override
  String get type => typeName;

  @override
  Json fields() => {'status': status.toJson()};
}

/// Either direction: a request on this socket failed.
final class ErrorMessage extends WsMessage {
  const ErrorMessage({required this.code, this.message});

  static const typeName = 'error';
  final String code;
  final String? message;

  @override
  String get type => typeName;

  @override
  Json fields() => {'code': code, if (message != null) 'message': message};
}

/// Viewer → Camera: start the full-session recording, or resume it when paused (SPEC §3.8).
/// [includeSeconds] > 0 also keeps that much of the buffer from before the press. The new state
/// arrives in the next [StatusUpdate]; a failure as [ErrorMessage] `rec_failed` or `no_space`.
final class RecStart extends WsMessage {
  const RecStart({this.includeSeconds = 0});

  static const typeName = 'rec_start';
  final int includeSeconds;

  @override
  String get type => typeName;

  @override
  Json fields() => {if (includeSeconds > 0) 'includeSeconds': includeSeconds};
}

/// Viewer → Camera: pause the recording at the end of the second in progress.
final class RecPause extends WsMessage {
  const RecPause();

  static const typeName = 'rec_pause';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

/// Viewer → Camera: finish the recording and save it to the Camera's gallery.
final class RecStop extends WsMessage {
  const RecStop();

  static const typeName = 'rec_stop';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

/// Camera → all viewers: a recording was saved to the Camera's gallery (Movies/InstantReplay).
final class RecordingFinished extends WsMessage {
  const RecordingFinished({required this.name, required this.parts, required this.durationMs, required this.reason});

  static const typeName = 'recording_finished';

  /// File name of the first part.
  final String name;
  final int parts;
  final int durationMs;
  final RecordingEndReason reason;

  @override
  String get type => typeName;

  @override
  Json fields() => {'name': name, 'parts': parts, 'durationMs': durationMs, 'reason': reason.name};
}

/// Viewer → Camera: change the scoreboard (SPEC §12.3). The new state arrives in the next
/// [StatusUpdate], sent at once.
final class ScoreboardCmd extends WsMessage {
  const ScoreboardCmd(this.command);

  static const typeName = 'scoreboard_cmd';
  final ScoreboardCommand command;

  @override
  String get type => typeName;

  @override
  Json fields() => command.toJson();
}

/// Viewer → Camera: where to stream. [key] null keeps the stored stream key.
final class BroadcastConfigure extends WsMessage {
  const BroadcastConfigure({
    this.server = BroadcastInfo.defaultServer,
    this.key,
    this.targetKbps = BroadcastInfo.defaultKbps,
    this.audio = true,
    this.replayScoreboard,
  });

  static const typeName = 'broadcast_config';
  final String server;
  final String? key;
  final int targetKbps;
  final bool audio;

  /// Scoreboard during replays on air; null keeps the stored choice.
  final bool? replayScoreboard;

  @override
  String get type => typeName;

  @override
  Json fields() => {
        'server': server,
        if (key != null) 'key': key,
        'targetKbps': targetKbps,
        'audio': audio,
        if (replayScoreboard != null) 'replayScoreboard': replayScoreboard,
      };
}

/// Viewer → Camera: go live. Failures come back as [ErrorMessage] `broadcast_failed`,
/// `not_configured` or `mic_permission`.
final class BroadcastStart extends WsMessage {
  const BroadcastStart();

  static const typeName = 'broadcast_start';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

/// Viewer → Camera: end the stream.
final class BroadcastStop extends WsMessage {
  const BroadcastStop();

  static const typeName = 'broadcast_stop';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

/// Viewer → Camera: zoom the camera to [ratio] (clamped to 1…`status.zoom.max`). The new value
/// arrives in the next [StatusUpdate], sent at once.
final class CameraZoom extends WsMessage {
  const CameraZoom({required this.ratio});

  static const typeName = 'camera_zoom';
  final double ratio;

  @override
  String get type => typeName;

  @override
  Json fields() => {'ratio': ratio};
}

/// Viewer → Camera: keep the [size] most recent acknowledged clips for replays on air (SPEC §3.4);
/// 0 deletes clips on ACK. The new size arrives in the next [StatusUpdate].
final class ClipReserve extends WsMessage {
  const ClipReserve({required this.size});

  static const typeName = 'clip_reserve';
  final int size;

  @override
  String get type => typeName;

  @override
  Json fields() => {'size': size};
}

/// Viewer → Camera: put clip [clipId] on air at [speed] (SPEC §12.6), replacing any replay on air.
/// Errors: `not_live`, `replay_unavailable`, `replay_failed`. `status.replay` follows.
final class ReplayAir extends WsMessage {
  const ReplayAir({required this.clipId, this.speed = 1});

  static const typeName = 'replay_air';
  final String clipId;
  final double speed;

  @override
  String get type => typeName;

  @override
  Json fields() => {'clipId': clipId, 'speed': speed};
}

/// Viewer → Camera: change the speed of the replay on air.
final class ReplaySpeed extends WsMessage {
  const ReplaySpeed({required this.speed});

  static const typeName = 'replay_speed';
  final double speed;

  @override
  String get type => typeName;

  @override
  Json fields() => {'speed': speed};
}

/// Viewer → Camera: cut back to the live picture.
final class ReplayStop extends WsMessage {
  const ReplayStop();

  static const typeName = 'replay_stop';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

/// Camera → all viewers, about 5 times a second while the stream's microphone is open (muted or
/// not): what it hears, for the mic button's meter (SPEC §12.7). [db] is dBFS (−90…0, one
/// decimal); null once when the microphone closes. Older viewers ignore it (unknown type).
final class MicLevel extends WsMessage {
  const MicLevel({required this.db});

  static const typeName = 'mic_level';
  final double? db;

  @override
  String get type => typeName;

  @override
  Json fields() => {if (db case final d?) 'db': (d * 10).roundToDouble() / 10};
}

/// Viewer → Camera: run [action] with the Camera's YouTube account (SPEC §12.1). Viewers never
/// call YouTube: the Camera does, and answers the sender with [YouTubeResult] carrying the same
/// [requestId]; every viewer sees the new state in `status.youtube`. [title], [description] and
/// [privacy] (`public`, `unlisted`, `private`) are for [YouTubeAction.save] and
/// [YouTubeAction.create]. Older Cameras ignore it (unknown type).
final class YouTubeCmd extends WsMessage {
  const YouTubeCmd({required this.requestId, required this.action, this.title, this.description, this.privacy});

  static const typeName = 'youtube_cmd';
  final String requestId;
  final YouTubeAction action;
  final String? title;
  final String? description;
  final String? privacy;

  @override
  String get type => typeName;

  @override
  Json fields() => {
        'requestId': requestId,
        'action': action.name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (privacy != null) 'privacy': privacy,
      };
}

/// Camera → the viewer that sent a [YouTubeCmd]: done ([errorCode] null) or failed. [status] is
/// the YouTube state after the command (the same as the next `status.youtube`), and [server]
/// the ingest address the Camera now streams to after `save`, `create` or `prepare` (never the
/// key). Error codes: those of the account (`not_signed_in`, `live_not_enabled`, `quota`,
/// `forbidden`, `network`, `api`), `unavailable` (no account on this Camera) and
/// `not_broadcast_mode`.
final class YouTubeResult extends WsMessage {
  const YouTubeResult({required this.requestId, this.status, this.server, this.errorCode, this.errorMessage});

  static const typeName = 'youtube_result';
  final String requestId;
  final YouTubeStatus? status;
  final String? server;
  final String? errorCode;
  final String? errorMessage;

  bool get ok => errorCode == null;

  @override
  String get type => typeName;

  @override
  Json fields() => {
        'requestId': requestId,
        if (status != null) 'status': status!.toJson(),
        if (server != null) 'server': server,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };
}

/// Keep-alive: the Viewer pings every 5 s; the Camera drops a viewer silent for 15 s.
final class Ping extends WsMessage {
  const Ping();

  static const typeName = 'ping';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

final class Pong extends WsMessage {
  const Pong();

  static const typeName = 'pong';

  @override
  String get type => typeName;

  @override
  Json fields() => const {};
}

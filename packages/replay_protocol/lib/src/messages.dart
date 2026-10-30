/// WebSocket messages of API v1: JSON objects `{"type": ..., ...fields}` (SPEC §4.2).
///
/// Live view signaling uses trickle ICE: the Camera sends its offer right away and both sides
/// exchange candidates as they are found, so a slow or empty gathering never blocks the call.
library;

import 'dart:convert';

import 'models.dart';

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

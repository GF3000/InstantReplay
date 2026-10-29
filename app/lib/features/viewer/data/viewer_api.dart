import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:replay_protocol/replay_protocol.dart';

/// The Camera rejected the token or the pairing code (401/403).
class UnauthorizedException implements Exception {
  const UnauthorizedException();

  @override
  String toString() => 'UnauthorizedException';
}

/// Any other non-success HTTP status.
class ApiException implements Exception {
  const ApiException(this.statusCode, [this.body]);

  final int statusCode;
  final String? body;

  @override
  String toString() => 'ApiException($statusCode${body == null || body!.isEmpty ? '' : ': $body'})';
}

/// Normalizes a user-typed or page address to `scheme://host:port`, without path or query.
/// Returns null when it is not an http(s) address with a host.
Uri? normalizeCameraAddress(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : defaultPort);
  return Uri(scheme: uri.scheme, host: uri.host, port: port);
}

/// Key that identifies one Camera in local storage.
String cameraKey(Uri base) => '${base.scheme}://${base.host}:${base.port}';

/// REST client of API v1 for one Camera. Works on web (BrowserClient) and Android (IOClient).
class ViewerApi {
  ViewerApi({required this.client, required this.base, this.token});

  final http.Client client;

  /// `scheme://host:port` of the Camera.
  final Uri base;
  final String? token;

  Uri _uri(String path) => base.replace(path: path);

  Map<String, String> get _auth => {if (token != null) 'Authorization': '${Api.bearer} $token'};

  Map<String, String> get _json => {..._auth, 'Content-Type': 'application/json'};

  /// WebSocket URL with the token as query parameter (browsers cannot set headers on WebSockets).
  Uri get wsUri => base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: Api.ws,
        queryParameters: {if (token != null) Api.tokenParam: token},
      );

  /// Exchanges the 6-digit code for the session token.
  Future<String> pair(String code) async {
    final res = await client.post(_uri(Api.pair), headers: _json, body: jsonEncode(PairRequest(code: code).toJson()));
    _check(res);
    return PairResponse.fromJson(jsonDecode(res.body) as Json).token;
  }

  Future<CameraInfo> info() async {
    final res = await client.get(_uri(Api.info), headers: _auth);
    _check(res);
    return CameraInfo.fromJson(jsonDecode(res.body) as Json);
  }

  /// Asks the Camera to cut a clip. Idempotent on [SaveClipRequest.requestId].
  Future<ClipDto> saveClip(SaveClipRequest request) async {
    final res = await client.post(_uri(Api.clips), headers: _json, body: jsonEncode(request.toJson()));
    _check(res);
    return ClipDto.fromJson(jsonDecode(res.body) as Json);
  }

  /// The Camera's outbox, for recovery after a reconnect.
  Future<List<ClipDto>> listClips() async {
    final res = await client.get(_uri(Api.clips), headers: _auth);
    _check(res);
    return [for (final j in jsonDecode(res.body) as List<Object?>) ClipDto.fromJson(j! as Json)];
  }

  /// Downloads a clip file. [onProgress] gets (received, total); total is null when unknown.
  Future<Uint8List> downloadClip(String id, {void Function(int received, int? total)? onProgress}) async {
    final req = http.Request('GET', _uri(Api.clip(id)))..headers.addAll(_auth);
    final res = await client.send(req);
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString().catchError((_) => '');
      _checkStatus(res.statusCode, body);
    }
    final total = res.contentLength;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      out.add(chunk);
      onProgress?.call(out.length, total);
    }
    return out.takeBytes();
  }

  /// Confirms a verified download so the Camera can release it. Throws [ApiException] 409 on a hash mismatch.
  Future<void> ack(String id, String sha256) async {
    final res = await client.post(_uri(Api.ack(id)), headers: _json, body: jsonEncode(AckRequest(sha256: sha256).toJson()));
    _check(res);
  }

  static void _check(http.Response res) => _checkStatus(res.statusCode, res.body);

  static void _checkStatus(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) throw const UnauthorizedException();
    throw ApiException(status, body);
  }
}

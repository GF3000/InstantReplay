import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show PlatformException;
import 'package:replay_capture_android/replay_capture_android.dart' as cap;
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../camera/capture_layer.dart';
import 'api_server.dart';
import 'pairing.dart';
import 'protocol_mapping.dart';

/// The Camera's API v1 server (SPEC §4): pairing, clips, downloads, acks, the WebSocket hub for
/// events and live-view signaling, and the bundled web viewer at `/`.
///
/// Uses dart:io, so it is only reachable through `server_platform.dart` on native builds.
class CameraServer implements ApiServer {
  CameraServer({
    required this.capture,
    required this.secrets,
    required this.cameraInfo,
    this.webRoot,
    this.saveTimeout = const Duration(seconds: 5),
    this.silenceTimeout = const Duration(seconds: 15),
    AttemptLimiter? pairLimiter,
  }) : _pairLimiter = pairLimiter ?? AttemptLimiter();

  final CaptureLayer capture;
  final PairingSecrets secrets;

  /// Read on every `/info` and `welcome`, so the profile is current.
  final CameraInfo Function() cameraInfo;

  /// Directory with the web viewer's `index.html`; null when this build has none.
  final String? webRoot;

  /// How long `POST /clips` waits for the outbox to register the clip.
  final Duration saveTimeout;

  /// Viewers silent for this long are dropped (they ping every 5 s).
  final Duration silenceTimeout;

  final AttemptLimiter _pairLimiter;
  final _sockets = <_ViewerSocket>{};

  /// Viewer whose PeerConnection the plugin holds, per viewer id.
  final _liveOwners = <String, _ViewerSocket>{};

  /// requestId → viewerId, so outbox events can say who asked for each clip (D9).
  final _requestedBy = <String, String>{};
  final _pendingSaves = <String, Future<ClipDto>>{};
  final _viewerCount = StreamController<int>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  CameraStatus? _lastStatus;
  DateTime? _lastStatusSent;
  Timer? _sweep;
  HttpServer? _server;

  /// Viewers that completed the WebSocket handshake.
  int get viewerCount => _sockets.where((s) => s.greeted).length;

  @override
  Stream<int> get viewerCountChanges => _viewerCount.stream;

  /// Binds and returns the port (useful with port 0 in tests).
  @override
  Future<int> start({Object? address, int port = defaultPort}) async {
    _subs
      ..add(capture.clipChanges.listen(_onClipChanged))
      ..add(capture.liveIceCandidates.listen(_onLocalIce))
      ..add(capture.stats.listen(_onStats));
    final sweepEvery = Duration(milliseconds: max(100, silenceTimeout.inMilliseconds ~/ 3));
    _sweep = Timer.periodic(sweepEvery, (_) => _dropSilent());
    final server = await shelf_io.serve(handler, address ?? InternetAddress.anyIPv4, port);
    server.autoCompress = false; // fMP4 does not compress and Range needs exact byte offsets.
    _server = server;
    return server.port;
  }

  @override
  Future<void> close() async {
    _sweep?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final s in _sockets.toList()) {
      _closeSocket(s, WsCloseCodes.shutdown);
    }
    await _server?.close(force: true);
    _server = null;
    await _viewerCount.close();
  }

  // region HTTP

  Handler get handler {
    final router = Router(notFoundHandler: _static)
      ..post(Api.pair, _pair)
      ..get(Api.info, _info)
      ..post(Api.clips, _saveClip)
      ..get(Api.clips, _listClips)
      ..get(Api.ws, webSocketHandler(_onSocket))
      ..get('${Api.clips}/<id>', _download)
      ..post('${Api.clips}/<id>/ack', _ack);
    return const Pipeline().addMiddleware(_cors).addMiddleware(_auth).addHandler(router.call);
  }

  /// The web viewer is same-origin; CORS only helps a viewer served from a dev machine. The token,
  /// not the origin, is the access control.
  static const _corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type, range',
    'access-control-expose-headers': 'content-length, content-range, accept-ranges',
  };

  static Handler _cors(Handler inner) => (request) async {
        if (request.method == 'OPTIONS') return Response(HttpStatus.noContent, headers: _corsHeaders);
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };

  Handler _auth(Handler inner) => (request) {
        final path = '/${request.url.path}';
        final protected = path.startsWith('${Api.prefix}/') && path != Api.pair;
        if (protected && !_authorized(request)) return _error(HttpStatus.unauthorized, 'unauthorized');
        return inner(request);
      };

  bool _authorized(Request request) {
    final header = request.headers[HttpHeaders.authorizationHeader];
    const scheme = '${Api.bearer} ';
    if (header != null && header.startsWith(scheme) && secrets.matchesToken(header.substring(scheme.length).trim())) {
      return true;
    }
    return secrets.matchesToken(request.url.queryParameters[Api.tokenParam]);
  }

  Future<Response> _pair(Request request) async {
    if (!_pairLimiter.tryAcquire(_remoteAddress(request))) {
      return _error(HttpStatus.tooManyRequests, 'rate_limited', 'Too many attempts; wait a minute.',
          {HttpHeaders.retryAfterHeader: '60'});
    }
    final PairRequest body;
    try {
      body = PairRequest.fromJson(await _readJson(request));
    } catch (_) {
      return _error(HttpStatus.badRequest, 'bad_request');
    }
    if (!secrets.matchesCode(body.code)) return _error(HttpStatus.forbidden, 'wrong_code');
    return _json(PairResponse(token: secrets.token).toJson());
  }

  Response _info(Request _) => _json(cameraInfo().toJson());

  Future<Response> _saveClip(Request request) async {
    final SaveClipRequest body;
    try {
      body = SaveClipRequest.fromJson(await _readJson(request));
    } catch (_) {
      return _error(HttpStatus.badRequest, 'bad_request');
    }
    if (body.requestId.isEmpty || body.preSeconds <= 0 || body.postSeconds < 0) {
      return _error(HttpStatus.badRequest, 'bad_request', 'preSeconds must be > 0 and postSeconds >= 0.');
    }
    try {
      return _json((await _save(body)).toJson(), status: HttpStatus.accepted);
    } on TimeoutException {
      return _error(HttpStatus.serviceUnavailable, 'save_timeout');
    } catch (e) {
      return _error(HttpStatus.internalServerError, 'save_failed', _describe(e));
    }
  }

  /// Starts the save and answers as soon as the outbox has the clip (normally `recording`), without
  /// waiting for the post-roll. Retries with the same requestId share the first request.
  Future<ClipDto> _save(SaveClipRequest r) {
    final viewerId = r.viewerId;
    if (viewerId != null) _requestedBy.putIfAbsent(r.requestId, () => viewerId);
    // A block body: returning the removed future from whenComplete would make it wait on itself.
    return _pendingSaves[r.requestId] ??= _startSave(r).whenComplete(() {
      _pendingSaves.remove(r.requestId);
    });
  }

  Future<ClipDto> _startSave(SaveClipRequest r) async {
    final known = (await capture.listClips()).where((c) => c.requestId == r.requestId).firstOrNull;
    if (known != null) return _dto(known);

    final registered = Completer<cap.ClipInfo>();
    void complete(cap.ClipInfo c) {
      if (!registered.isCompleted) registered.complete(c);
    }

    final sub = capture.clipChanges.where((c) => c.requestId == r.requestId).listen(complete);
    try {
      unawaited(capture
          .saveClip(requestId: r.requestId, preSeconds: r.preSeconds, postSeconds: r.postSeconds)
          .then(complete, onError: (Object e, StackTrace st) {
        if (!registered.isCompleted) registered.completeError(e, st);
      }));
      return _dto(await registered.future.timeout(saveTimeout));
    } finally {
      await sub.cancel();
    }
  }

  Future<Response> _listClips(Request _) async =>
      _json([for (final c in await capture.listClips()) _dto(c).toJson()]);

  /// The clip file with single-range support, for seeking players and resumable downloads.
  Future<Response> _download(Request request, String id) async {
    final clip = await capture.getClip(id);
    final path = clip?.path;
    if (clip == null || clip.state != cap.ClipState.ready || path == null) return _error(HttpStatus.notFound, 'not_found');
    final file = File(path);
    if (!file.existsSync()) return _error(HttpStatus.notFound, 'not_found');
    final length = await file.length();
    final headers = {
      HttpHeaders.contentTypeHeader: 'video/mp4',
      HttpHeaders.acceptRangesHeader: 'bytes',
      HttpHeaders.cacheControlHeader: 'no-store',
    };

    final range = _parseRange(request.headers[HttpHeaders.rangeHeader], length);
    if (range == _unsatisfiable) {
      return Response(HttpStatus.requestedRangeNotSatisfiable,
          headers: {...headers, HttpHeaders.contentRangeHeader: 'bytes */$length'});
    }
    if (range != null) {
      final (start, end) = range;
      return Response(
        HttpStatus.partialContent,
        body: request.method == 'HEAD' ? null : file.openRead(start, end + 1),
        headers: {
          ...headers,
          HttpHeaders.contentRangeHeader: 'bytes $start-$end/$length',
          HttpHeaders.contentLengthHeader: '${end - start + 1}',
        },
      );
    }
    return Response.ok(
      request.method == 'HEAD' ? null : file.openRead(),
      headers: {...headers, HttpHeaders.contentLengthHeader: '$length'},
    );
  }

  static const _unsatisfiable = (-1, -1);

  /// `bytes=a-b`, `bytes=a-` or `bytes=-n` → inclusive (start, end); null means send everything
  /// (no header, or a form we do not support such as multiple ranges).
  static (int, int)? _parseRange(String? header, int length) {
    if (header == null) return null;
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return null;
    final first = m[1]!, last = m[2]!;
    if (first.isEmpty && last.isEmpty) return null;
    final int start, end;
    if (first.isEmpty) {
      final suffix = int.parse(last);
      if (suffix == 0) return _unsatisfiable;
      start = max(0, length - suffix);
      end = length - 1;
    } else {
      start = int.parse(first);
      end = last.isEmpty ? length - 1 : min(int.parse(last), length - 1);
    }
    if (start >= length || start > end) return _unsatisfiable;
    return (start, end);
  }

  Future<Response> _ack(Request request, String id) async {
    final AckRequest body;
    try {
      body = AckRequest.fromJson(await _readJson(request));
    } catch (_) {
      return _error(HttpStatus.badRequest, 'bad_request');
    }
    if (await capture.getClip(id) == null) return _error(HttpStatus.notFound, 'not_found');
    try {
      final ok = await capture.ackClip(id, body.sha256);
      return ok ? Response(HttpStatus.noContent) : _error(HttpStatus.conflict, 'hash_mismatch');
    } catch (e) {
      return _error(HttpStatus.internalServerError, 'ack_failed', _describe(e));
    }
  }

  /// The web viewer, with SPA fallback to `index.html` for client-side routes.
  late final Handler _static = _buildStaticHandler();

  Handler _buildStaticHandler() {
    final root = webRoot;
    if (root == null) {
      return (request) => request.url.path.startsWith('api/')
          ? _error(HttpStatus.notFound, 'not_found')
          : Response.ok(_noBundlePage, headers: {HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8'});
    }
    final files = createStaticHandler(root, defaultDocument: 'index.html');
    final index = File('$root${Platform.pathSeparator}index.html');
    return (request) async {
      if (request.url.path.startsWith('api/')) return _error(HttpStatus.notFound, 'not_found');
      if (request.method != 'GET' && request.method != 'HEAD') return Response(HttpStatus.methodNotAllowed);
      final response = await files(request);
      if (response.statusCode != HttpStatus.notFound) return response;
      return Response.ok(
        request.method == 'HEAD' ? null : index.openRead(),
        headers: {HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8', HttpHeaders.cacheControlHeader: 'no-cache'},
      );
    };
  }

  static const _noBundlePage = '''
<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>InstantReplay</title>
<body style="font:16px system-ui;background:#111;color:#eee;margin:24px">
<h1>InstantReplay Camera</h1>
<p>The web viewer is not bundled in this build. Use the InstantReplay app as the Viewer, or install a
build that includes the web viewer.</p>
<p>El visor web no está incluido en esta compilación. Usa la app InstantReplay como Visor, o instala una
compilación que incluya el visor web.</p>
''';

  // endregion

  // region WebSocket

  void _onSocket(WebSocketChannel channel, String? _) {
    final socket = _ViewerSocket(channel, DateTime.now());
    _sockets.add(socket);
    channel.stream.listen(
      (raw) => unawaited(_onMessage(socket, raw)),
      onDone: () => _onSocketGone(socket),
      onError: (Object _) => _onSocketGone(socket),
    );
  }

  Future<void> _onMessage(_ViewerSocket s, Object? raw) async {
    s.lastSeen = DateTime.now();
    final WsMessage? message;
    try {
      message = raw is String ? WsMessage.decode(raw) : throw const FormatException('binary frame');
    } catch (_) {
      s.send(const ErrorMessage(code: 'bad_message'));
      return;
    }
    if (message == null) return; // A newer viewer's message type.
    if (!s.greeted && message is! Hello && message is! Ping) {
      s.send(const ErrorMessage(code: 'hello_required', message: 'Send hello first.'));
      return;
    }
    try {
      switch (message) {
        case Hello():
          _onHello(s, message);
        case Ping():
          s.send(const Pong());
        case LiveStart(:final codec):
          await _startLive(s, codec);
        case LiveStop():
          await _stopLive(s);
        case RtcAnswer(:final sdp):
          if (_liveOwners[s.viewerId] == s) await capture.liveAnswer(s.viewerId!, sdp);
        case RtcIce(:final candidate, :final sdpMid, :final sdpMLineIndex):
          if (_liveOwners[s.viewerId] == s) {
            await capture.liveAddIceCandidate(s.viewerId!, candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex);
          }
        case Welcome() || RtcOffer() || ClipChanged() || StatusUpdate() || ErrorMessage() || Pong():
          break; // Camera → Viewer messages; nothing to do.
      }
    } catch (e) {
      s.send(ErrorMessage(code: message is LiveStart ? 'live_failed' : 'failed', message: _describe(e)));
    }
  }

  void _onHello(_ViewerSocket s, Hello hello) {
    if (hello.protocolVersion != protocolVersion) {
      s.send(ErrorMessage(
        code: 'unsupported_protocol',
        message: 'Camera speaks protocol $protocolVersion, viewer ${hello.protocolVersion}.',
      ));
      _closeSocket(s, WsCloseCodes.unsupportedProtocol);
      return;
    }
    final wasGreeted = s.greeted;
    s.viewerId ??= hello.viewerId;
    s.send(Welcome(camera: cameraInfo()));
    final status = _lastStatus;
    if (status != null) s.send(StatusUpdate(status: status));
    if (!wasGreeted) _emitViewerCount();
  }

  Future<void> _startLive(_ViewerSocket s, String codec) async {
    final id = s.viewerId!;
    final previous = _liveOwners[id];
    if (previous != null && previous != s) previous.pendingIce = null;
    _liveOwners[id] = s;
    // Candidates can overtake the offer; hold them until it is sent.
    final pending = s.pendingIce = <RtcIce>[];
    try {
      final sdp = await capture.liveOffer(id, codec: codec);
      if (_liveOwners[id] != s || s.pendingIce != pending) return; // Stopped or replaced meanwhile.
      s.send(RtcOffer(sdp: sdp));
      pending.forEach(s.send);
    } catch (_) {
      if (_liveOwners[id] == s) _liveOwners.remove(id);
      rethrow;
    } finally {
      if (s.pendingIce == pending) s.pendingIce = null;
    }
  }

  Future<void> _stopLive(_ViewerSocket s) async {
    final id = s.viewerId;
    if (id == null || _liveOwners[id] != s) return;
    _liveOwners.remove(id);
    s.pendingIce = null;
    await capture.liveClose(id);
  }

  void _onLocalIce(cap.LiveIceCandidate c) {
    final s = _liveOwners[c.viewerId];
    if (s == null) return;
    final message = RtcIce(candidate: c.candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex);
    final pending = s.pendingIce;
    pending == null ? s.send(message) : pending.add(message);
  }

  void _onClipChanged(cap.ClipInfo c) => _broadcast(ClipChanged(clip: _dto(c)));

  void _onStats(cap.CaptureStats stats) {
    final status = _lastStatus = cameraStatus(stats);
    final now = DateTime.now();
    final last = _lastStatusSent;
    if (last != null && now.difference(last) < const Duration(milliseconds: 900)) return;
    _lastStatusSent = now;
    _broadcast(StatusUpdate(status: status));
  }

  void _broadcast(WsMessage message) {
    final encoded = message.encode();
    for (final s in _sockets) {
      if (s.greeted) s.sendRaw(encoded);
    }
  }

  void _dropSilent() {
    final now = DateTime.now();
    for (final s in _sockets.where((s) => now.difference(s.lastSeen) > silenceTimeout).toList()) {
      _closeSocket(s, WsCloseCodes.silent);
    }
  }

  void _closeSocket(_ViewerSocket s, int code) {
    try {
      unawaited(s.channel.sink.close(code).catchError((Object _) {}));
    } catch (_) {
      // Already closing.
    }
    _onSocketGone(s);
  }

  void _onSocketGone(_ViewerSocket s) {
    if (!_sockets.remove(s)) return;
    final id = s.viewerId;
    if (id != null && _liveOwners[id] == s) {
      _liveOwners.remove(id);
      unawaited(capture.liveClose(id).catchError((Object _) {}));
    }
    if (s.greeted) _emitViewerCount();
  }

  void _emitViewerCount() {
    if (!_viewerCount.isClosed) _viewerCount.add(viewerCount);
  }

  // endregion

  ClipDto _dto(cap.ClipInfo c) => clipDto(c, requestedBy: _requestedBy[c.requestId]);

  static String _remoteAddress(Request request) =>
      (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? 'local';

  static Future<Json> _readJson(Request request) async => jsonDecode(await request.readAsString()) as Json;

  static Response _json(Object body, {int status = HttpStatus.ok}) => Response(
        status,
        body: jsonEncode(body),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );

  static Response _error(int status, String code, [String? message, Map<String, String> headers = const {}]) =>
      Response(
        status,
        body: jsonEncode(ErrorMessage(code: code, message: message).fields()),
        headers: {HttpHeaders.contentTypeHeader: 'application/json', ...headers},
      );

  static String _describe(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';
}

class _ViewerSocket {
  _ViewerSocket(this.channel, this.lastSeen);

  final WebSocketChannel channel;
  DateTime lastSeen;

  /// Set by `hello`.
  String? viewerId;

  /// Local candidates held while this viewer's offer is being created.
  List<RtcIce>? pendingIce;

  bool get greeted => viewerId != null;

  void send(WsMessage message) => sendRaw(message.encode());

  void sendRaw(String encoded) {
    try {
      channel.sink.add(encoded);
    } catch (_) {
      // Closed under us; the stream's onDone cleans up.
    }
  }
}

/// Close codes the Camera sends. Servers built on `package:web_socket` may only send 1000 or
/// 3000–4999, so the specific reasons are application codes.
abstract final class WsCloseCodes {
  static const shutdown = 1000;

  /// No message (not even a ping) for the silence timeout.
  static const silent = 4001;
  static const unsupportedProtocol = 4002;
}

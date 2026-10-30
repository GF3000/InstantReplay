import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'viewer_api.dart';

/// A text WebSocket, behind an interface so tests do not need a server.
abstract class SessionChannel {
  Stream<String> get incoming;
  void send(String text);
  Future<void> close();
}

typedef ChannelConnector = Future<SessionChannel> Function(Uri uri);

/// [ChannelConnector] backed by `web_socket_channel` (web and Android).
Future<SessionChannel> connectWebSocket(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready;
  return _WsChannel(channel);
}

class _WsChannel implements SessionChannel {
  _WsChannel(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get incoming => _channel.stream.where((m) => m is String).cast<String>();

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() => _channel.sink.close();
}

enum LinkPhase {
  /// First attempt.
  connecting,

  /// Hello/Welcome done; messages flow.
  connected,

  /// Lost or failed; waiting for the next attempt.
  reconnecting,

  /// The token was rejected. The link stops; the user must pair again.
  unauthorized,

  /// The Camera speaks another protocol version. The link stops.
  incompatible,
}

@immutable
class LinkState {
  const LinkState({required this.phase, this.camera, this.status, this.error});

  final LinkPhase phase;

  /// From the last Welcome.
  final CameraInfo? camera;

  /// Latest StatusUpdate; kept while reconnecting so the UI does not flicker.
  final CameraStatus? status;
  final String? error;

  LinkState copyWith({LinkPhase? phase, CameraInfo? camera, CameraStatus? status, String? Function()? error}) =>
      LinkState(
        phase: phase ?? this.phase,
        camera: camera ?? this.camera,
        status: status ?? this.status,
        error: error == null ? this.error : error(),
      );
}

/// The Viewer's WebSocket session with one Camera (SPEC §4.2): Hello → Welcome, ping every 5 s,
/// reconnect with backoff, and a broadcast stream of every incoming message.
class SessionLink {
  SessionLink({
    required this.api,
    required this.viewerId,
    ChannelConnector? connect,
    this.pingInterval = const Duration(seconds: 5),
    this.silenceTimeout = const Duration(seconds: 15),
    this.welcomeTimeout = const Duration(seconds: 5),
    this.backoff = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
  }) : _connect = connect ?? connectWebSocket;

  final ViewerApi api;
  final String viewerId;
  final ChannelConnector _connect;
  final Duration pingInterval;
  final Duration silenceTimeout;
  final Duration welcomeTimeout;
  final List<Duration> backoff;

  final _messages = StreamController<WsMessage>.broadcast();
  final _states = StreamController<LinkState>.broadcast();
  LinkState _state = const LinkState(phase: LinkPhase.connecting);
  SessionChannel? _channel;
  Completer<void>? _wake;
  bool _started = false;
  bool _disposed = false;

  /// Every decoded message from the Camera, Welcome included.
  Stream<WsMessage> get messages => _messages.stream;
  Stream<LinkState> get states => _states.stream;
  LinkState get state => _state;
  bool get isConnected => _state.phase == LinkPhase.connected;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  /// Sends when connected; returns false (and drops the message) otherwise.
  bool send(WsMessage message) {
    final ch = _channel;
    if (ch == null || !isConnected) return false;
    try {
      ch.send(message.encode());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Skips the current backoff wait, e.g. when the app returns to the foreground.
  void retryNow() => _wakeUp();

  void _wakeUp() {
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> dispose() async {
    _disposed = true;
    _wakeUp();
    await _channel?.close();
    _channel = null;
    await _messages.close();
    await _states.close();
  }

  void _set(LinkState s) {
    if (_disposed) return;
    _state = s;
    _states.add(s);
  }

  Future<void> _run() async {
    var failures = 0;
    while (!_disposed) {
      try {
        // A cheap authenticated call tells "wrong token" apart from "unreachable" before the socket.
        await api.info();
        if (_disposed) return;
        await _session();
        failures = 0;
      } on UnauthorizedException {
        _set(_state.copyWith(phase: LinkPhase.unauthorized));
        return;
      } on _IncompatibleCamera catch (e) {
        _set(_state.copyWith(phase: LinkPhase.incompatible, camera: e.camera));
        return;
      } catch (e) {
        if (_disposed) return;
        _set(_state.copyWith(phase: LinkPhase.reconnecting, error: () => '$e'));
      }
      if (_disposed) return;
      if (_state.phase == LinkPhase.connected) _set(_state.copyWith(phase: LinkPhase.reconnecting));
      final wait = backoff[min(failures, backoff.length - 1)];
      failures++;
      _wake = Completer<void>();
      await Future.any([Future<void>.delayed(wait), _wake!.future]);
      _wake = null;
    }
  }

  /// One socket from connect to close. Returns normally when the socket ends.
  Future<void> _session() async {
    final ch = await _connect(api.wsUri);
    if (_disposed) {
      await ch.close();
      return;
    }
    _channel = ch;
    final done = Completer<void>();
    final welcomed = Completer<CameraInfo>();
    var lastHeard = DateTime.now();
    Timer? ping;

    final sub = ch.incoming.listen(
      (raw) {
        lastHeard = DateTime.now();
        final WsMessage? msg;
        try {
          msg = WsMessage.decode(raw);
        } catch (_) {
          return; // Malformed: ignore rather than drop the session.
        }
        if (msg == null) return;
        switch (msg) {
          case Welcome(:final camera):
            if (!welcomed.isCompleted) welcomed.complete(camera);
          case StatusUpdate(:final status):
            if (isConnected) _set(_state.copyWith(status: status));
          case Ping():
            ch.send(const Pong().encode());
          case RecordingFinished():
            // Only forwarded (the live screen tells the coach); the idle state that follows comes
            // in its own StatusUpdate, so the link state is not touched here.
            break;
          default:
        }
        if (!_messages.isClosed) _messages.add(msg);
      },
      onError: (Object e) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    try {
      ch.send(Hello(protocolVersion: protocolVersion, viewerId: viewerId).encode());
      final camera = await Future.any([
        welcomed.future,
        done.future.then<CameraInfo>((_) => throw StateError('closed before welcome')),
      ]).timeout(welcomeTimeout);
      if (camera.protocolVersion != protocolVersion) throw _IncompatibleCamera(camera);
      _set(LinkState(phase: LinkPhase.connected, camera: camera, status: _state.status));
      ping = Timer.periodic(pingInterval, (_) {
        if (DateTime.now().difference(lastHeard) > silenceTimeout) {
          if (!done.isCompleted) done.complete();
          return;
        }
        try {
          ch.send(const Ping().encode());
        } catch (_) {
          if (!done.isCompleted) done.complete();
        }
      });
      await done.future;
    } finally {
      ping?.cancel();
      await sub.cancel();
      _channel = null;
      unawaited(ch.close().catchError((_) {}));
    }
  }
}

class _IncompatibleCamera implements Exception {
  const _IncompatibleCamera(this.camera);

  final CameraInfo camera;
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../core/preferences.dart';
import '../camera/camera_session.dart';
import '../camera/capture_layer.dart';
import 'api_server.dart';
import 'pairing.dart';

/// What the Camera screen shows about the server and pairing.
@immutable
class CameraServerState {
  const CameraServerState({
    required this.code,
    required this.token,
    this.running = false,
    this.port = defaultPort,
    this.address,
    this.viewers = 0,
    this.error,
  });

  /// The 6-digit pairing code.
  final String code;
  final String token;
  final bool running;
  final int port;

  /// Wi-Fi or hotspot IPv4; null when no network is up.
  final String? address;
  final int viewers;

  /// Why the server could not start (e.g. the port is taken).
  final String? error;

  /// What the QR encodes: opens the web viewer already paired.
  String? get url => address == null ? null : 'http://$address:$port/?${Api.tokenParam}=$token';

  CameraServerState copyWith({bool? running, int? port, String? Function()? address, int? viewers, String? Function()? error}) =>
      CameraServerState(
        code: code,
        token: token,
        running: running ?? this.running,
        port: port ?? this.port,
        address: address == null ? this.address : address(),
        viewers: viewers ?? this.viewers,
        error: error == null ? this.error : error(),
      );
}

/// Runs the API server for the Camera role: starts once capture first runs and stays up across
/// profile restarts, so viewers keep their token; stops when the Camera screen goes away.
class CameraServerNotifier extends Notifier<CameraServerState> {
  static const _addressRefresh = Duration(seconds: 5);

  ApiServer? _server;
  bool _starting = false;
  String? _profileId;
  String _deviceName = 'InstantReplay';
  StreamSubscription<int>? _viewerSub;
  Timer? _addressTimer;

  @override
  CameraServerState build() {
    final secrets = PairingSecrets.generate();
    ref.listen(cameraSessionProvider, (_, session) {
      _profileId = session.phase == CameraPhase.running ? session.profileId : null;
      if (session.phase == CameraPhase.running) unawaited(_start(secrets));
    }, fireImmediately: true);
    ref.onDispose(() {
      _addressTimer?.cancel();
      unawaited(_viewerSub?.cancel());
      final server = _server;
      _server = null;
      if (server != null) unawaited(server.close().catchError((Object _) {}));
    });
    return CameraServerState(code: secrets.code, token: secrets.token);
  }

  Future<void> _start(PairingSecrets secrets) async {
    if (_server != null || _starting) return;
    _starting = true;
    final platform = ref.read(serverPlatformProvider);
    final cameraId = ref.read(cameraIdProvider);
    ApiServer? server;
    try {
      _deviceName = await platform.deviceName().catchError((Object _) => _deviceName);
      if (!ref.mounted) return;
      server = await platform.createServer(ApiServerConfig(
        capture: ref.read(captureLayerProvider),
        secrets: secrets,
        cameraInfo: () => CameraInfo(
          protocolVersion: protocolVersion,
          cameraId: cameraId,
          name: _deviceName,
          profileId: _profileId,
        ),
      ));
      if (!ref.mounted) return;
      _viewerSub = server.viewerCountChanges.listen((n) {
        if (ref.mounted) state = state.copyWith(viewers: n);
      });
      final port = await server.start();
      if (!ref.mounted) {
        await server.close();
        return;
      }
      _server = server;
      state = state.copyWith(running: true, port: port, error: () => null);
      await _refreshAddress();
      _addressTimer = Timer.periodic(_addressRefresh, (_) => _refreshAddress());
    } catch (e) {
      if (server != null && _server != server) unawaited(server.close().catchError((Object _) {}));
      if (ref.mounted) state = state.copyWith(running: false, error: () => '$e');
    } finally {
      _starting = false;
    }
  }

  /// The hotspot or Wi-Fi may come up after the Camera screen, so keep looking.
  Future<void> _refreshAddress() async {
    final address = await ref.read(serverPlatformProvider).localAddress().catchError((Object _) => null);
    if (ref.mounted && address != state.address) state = state.copyWith(address: () => address);
  }
}

final cameraServerProvider =
    NotifierProvider.autoDispose<CameraServerNotifier, CameraServerState>(CameraServerNotifier.new);

/// Stable id of this Camera install, persisted on first use (`/info`, NSD TXT).
final cameraIdProvider = Provider<String>((ref) {
  const key = 'cameraId';
  final prefs = ref.watch(sharedPreferencesProvider);
  final existing = prefs.getString(key);
  if (existing != null && existing.isNotEmpty) return existing;
  final random = Random.secure();
  final id = List.generate(8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  unawaited(prefs.setString(key, id));
  return id;
});

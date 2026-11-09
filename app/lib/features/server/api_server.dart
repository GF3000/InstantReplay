import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../broadcast/broadcast_host.dart';
import '../camera/capture_layer.dart';
import '../discovery/nsd.dart';
import 'pairing.dart';
import 'server_platform.dart' as platform;

/// The running API v1 server, as the Camera screen sees it. Implemented by `CameraServer` on
/// native builds; tests use a fake.
abstract interface class ApiServer {
  /// Binds and returns the port.
  Future<int> start({Object? address, int port = defaultPort});

  Future<void> close();

  /// Number of viewers connected over WebSocket, on every change.
  Stream<int> get viewerCountChanges;

  /// Capture restarted (e.g. a profile change): the old live calls are gone. Viewers get a fresh
  /// `welcome` with the new profile and renegotiate their live view.
  void captureRestarted();
}

/// The Camera's zoom as the server sees it: rides on `status`, any viewer can change it.
abstract interface class ZoomHost {
  /// Null while capture is not running.
  ZoomInfo? get info;

  void set(double ratio);

  /// After every change, so the server pushes a status at once.
  Stream<void> get changes;
}

class ApiServerConfig {
  const ApiServerConfig({
    required this.capture,
    required this.secrets,
    required this.cameraInfo,
    this.broadcast,
    this.zoom,
  });

  final CaptureLayer capture;
  final PairingSecrets secrets;
  final CameraInfo Function() cameraInfo;

  /// Broadcast mode (SPEC §12): the scoreboard and the stream; null leaves it out.
  final BroadcastHost? broadcast;

  /// Camera zoom; null leaves it out of `status`.
  final ZoomHost? zoom;
}

/// Platform pieces of the server, injectable for tests. Web gets a stub that never runs (the
/// Camera role is Android-only).
class ServerPlatform {
  const ServerPlatform({
    required this.createServer,
    required this.localAddress,
    required this.deviceName,
    this.announce = _noAnnounce,
  });

  final Future<ApiServer> Function(ApiServerConfig config) createServer;

  /// IPv4 address of the Wi-Fi or hotspot interface viewers reach us on; null when offline.
  final Future<String?> Function() localAddress;

  /// Human-readable device name for `/info`, e.g. "Google Pixel 7".
  final Future<String> Function() deviceName;

  /// Announces the running server over NSD so native Viewers can list it; null when there is
  /// nothing to announce on (tests).
  final Future<NsdAnnouncement?> Function(NsdAdvert advert) announce;
}

Future<NsdAnnouncement?> _noAnnounce(NsdAdvert _) async => null;

/// The server publishes the native outbox and live view, so it only runs over the real capture
/// plugin; with any other capture layer (widget tests) it is inert unless a test overrides this.
final serverPlatformProvider = Provider<ServerPlatform>(
  (ref) => ref.watch(captureLayerProvider) is PluginCaptureLayer ? platform.serverPlatform : inertServerPlatform,
);

final inertServerPlatform = ServerPlatform(
  createServer: (_) async => _InertApiServer(),
  localAddress: () async => null,
  deviceName: () async => 'InstantReplay',
);

class _InertApiServer implements ApiServer {
  @override
  Future<int> start({Object? address, int port = defaultPort}) async => port;

  @override
  Future<void> close() async {}

  @override
  Stream<int> get viewerCountChanges => const Stream.empty();

  @override
  void captureRestarted() {}
}

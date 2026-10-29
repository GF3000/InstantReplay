import 'api_server.dart';

/// Web: the Camera role is unreachable, so nothing here runs.
final serverPlatform = ServerPlatform(
  createServer: (_) async => throw UnsupportedError('The Camera server needs dart:io.'),
  localAddress: () async => null,
  deviceName: () async => 'InstantReplay',
);

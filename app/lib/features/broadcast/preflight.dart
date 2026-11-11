import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preflight_stub.dart' if (dart.library.io) 'preflight_io.dart' as platform;

/// Whether YouTube's ingest server resolves from this device: the broadcast checklist's
/// "Internet" line (SPEC §12.7). Always false on the web, which never runs the Camera.
Future<bool> canReachStreamServer(String server) => platform.canReachStreamServer(server);

/// [canReachStreamServer], replaceable in tests (which must not touch the network).
final streamServerReachableProvider = Provider<Future<bool> Function(String server)>((_) => canReachStreamServer);

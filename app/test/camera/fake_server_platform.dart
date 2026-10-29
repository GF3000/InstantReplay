import 'dart:async';

import 'package:instant_replay/features/server/api_server.dart';

/// An API server that binds nothing; tests drive the viewer count by hand.
class FakeApiServer implements ApiServer {
  FakeApiServer(this.config);

  final ApiServerConfig config;
  final viewers = StreamController<int>.broadcast();
  bool started = false;
  bool closed = false;

  @override
  Future<int> start({Object? address, int port = 8080}) async {
    started = true;
    return port;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  Stream<int> get viewerCountChanges => viewers.stream;
}

class FakeServerPlatform {
  FakeServerPlatform({this.address = '192.168.43.1'});

  String? address;
  final servers = <FakeApiServer>[];

  FakeApiServer? get last => servers.lastOrNull;

  ServerPlatform get platform => ServerPlatform(
        createServer: (config) async => (servers..add(FakeApiServer(config))).last,
        localAddress: () async => address,
        deviceName: () async => 'Test Phone',
      );
}

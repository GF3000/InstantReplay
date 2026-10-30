import 'dart:async';

import 'package:instant_replay/features/discovery/nsd.dart';
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

  int restarts = 0;

  @override
  void captureRestarted() => restarts++;
}

/// Records an NSD announcement instead of publishing it.
class FakeAnnouncement implements NsdAnnouncement {
  FakeAnnouncement(this.advert);

  final NsdAdvert advert;
  bool stopped = false;

  @override
  Future<void> stop() async => stopped = true;
}

class FakeServerPlatform {
  FakeServerPlatform({this.address = '192.168.43.1'});

  String? address;
  final servers = <FakeApiServer>[];
  final announcements = <FakeAnnouncement>[];

  FakeApiServer? get last => servers.lastOrNull;

  ServerPlatform get platform => ServerPlatform(
        createServer: (config) async => (servers..add(FakeApiServer(config))).last,
        localAddress: () async => address,
        deviceName: () async => 'Test Phone',
        announce: (advert) async => (announcements..add(FakeAnnouncement(advert))).last,
      );
}

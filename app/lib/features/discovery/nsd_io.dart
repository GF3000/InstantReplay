import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'discovered_camera.dart';
import 'nsd.dart';

Future<NsdAnnouncement> announceCamera(NsdAdvert advert) async {
  final broadcast = BonsoirBroadcast(
    service: BonsoirService(name: advert.name, type: nsdServiceType, port: advert.port, attributes: advert.txt),
  );
  try {
    await broadcast.initialize();
    await broadcast.start();
  } catch (_) {
    unawaited(broadcast.stop().catchError((Object _) {}));
    rethrow;
  }
  return _BonsoirAnnouncement(broadcast);
}

class _BonsoirAnnouncement implements NsdAnnouncement {
  _BonsoirAnnouncement(this._broadcast);

  final BonsoirBroadcast _broadcast;

  @override
  Future<void> stop() => _broadcast.stop();
}

Stream<List<DiscoveredCamera>> browseCameras() {
  late final StreamController<List<DiscoveredCamera>> controller;
  BonsoirDiscovery? discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? events;
  var cameras = const DiscoveredCameras();
  var cancelled = false;

  void emit(DiscoveredCameras next) {
    if (identical(next, cameras)) return;
    cameras = next;
    if (!cancelled) controller.add(next.list);
  }

  Future<void> stop() async {
    final d = discovery;
    if (d != null && d.isReady && !d.isStopped) await d.stop().catchError((Object _) {});
  }

  Future<void> start() async {
    try {
      final d = BonsoirDiscovery(type: nsdServiceType);
      discovery = d;
      await d.initialize();
      if (cancelled) return stop();
      events = d.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            // Found services carry no address or TXT yet.
            unawaited(Future.sync(() => d.serviceResolver.resolveService(service)).catchError((Object e) {
              debugPrint('NSD resolve failed: $e');
            }));
          case BonsoirDiscoveryServiceResolvedEvent(:final service) || BonsoirDiscoveryServiceUpdatedEvent(:final service):
            final camera = DiscoveredCamera.fromService(
              serviceName: service.name,
              addresses: service.hostAddresses,
              port: service.port,
              txt: service.attributes,
            );
            emit(camera == null ? cameras.lost(service.name) : cameras.resolved(service.name, camera));
          case BonsoirDiscoveryServiceLostEvent(:final service):
            emit(cameras.lost(service.name));
          default:
        }
      });
      await d.start();
      if (cancelled) await stop();
    } catch (e) {
      // No NSD (e.g. tests, or the OS refused): the list just stays empty.
      debugPrint('NSD browse failed: $e');
    }
  }

  controller = StreamController<List<DiscoveredCamera>>(
    onListen: () {
      controller.add(const []);
      unawaited(start());
    },
    onCancel: () async {
      cancelled = true;
      await events?.cancel();
      await stop();
    },
  );
  return controller.stream;
}

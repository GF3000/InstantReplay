import 'discovered_camera.dart';
import 'nsd.dart';

// bonsoir needs dart:io, so web gets these.

Future<NsdAnnouncement> announceCamera(NsdAdvert advert) async =>
    throw UnsupportedError('NSD announce needs dart:io.');

Stream<List<DiscoveredCamera>> browseCameras() => Stream.value(const []);

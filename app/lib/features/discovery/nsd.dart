import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities.dart';
import 'discovered_camera.dart';
import 'nsd_stub.dart' if (dart.library.io) 'nsd_io.dart' as platform;

/// What the Camera announces: the service name (its device name; the OS may add a suffix on a
/// clash), the API port and the TXT record (see [cameraTxt]).
typedef NsdAdvert = ({String name, int port, Map<String, String> txt});

/// A running NSD announcement.
abstract interface class NsdAnnouncement {
  Future<void> stop();
}

/// Announces the Camera's server over NSD (`bonsoir` on Android; web never runs the Camera).
Future<NsdAnnouncement> announceCamera(NsdAdvert advert) => platform.announceCamera(advert);

/// Cameras on the network, updated as they come and go. Starts browsing on listen and stops on
/// cancel; emits an empty list first, and stays empty when NSD is unavailable.
typedef CameraBrowser = Stream<List<DiscoveredCamera>> Function();

/// Injection point for tests.
final cameraBrowserProvider = Provider<CameraBrowser>((_) => platform.browseCameras);

/// The native Viewer's list of Cameras; always empty on web (it relies on QR, code or same origin).
final discoveredCamerasProvider = StreamProvider.autoDispose<List<DiscoveredCamera>>((ref) {
  if (!ref.watch(capabilitiesProvider).canBrowseNsd) return Stream.value(const []);
  return ref.watch(cameraBrowserProvider)();
});

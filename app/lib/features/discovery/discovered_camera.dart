import 'package:flutter/foundation.dart';
import 'package:replay_protocol/replay_protocol.dart';

/// DNS-SD service type the Camera announces (SPEC §4).
const nsdServiceType = '_instantreplay._tcp';

/// TXT record keys (SPEC §4: `{v, cameraId, name}`).
abstract final class NsdTxt {
  static const version = 'v';
  static const cameraId = 'cameraId';
  static const name = 'name';
}

/// What the Camera publishes in its TXT record.
Map<String, String> cameraTxt({required String cameraId, required String name}) => {
      NsdTxt.version: '$protocolVersion',
      NsdTxt.cameraId: cameraId,
      NsdTxt.name: name,
    };

/// A Camera found over NSD and resolved to an address.
@immutable
class DiscoveredCamera {
  const DiscoveredCamera({
    required this.cameraId,
    required this.name,
    required this.host,
    required this.port,
    this.version = protocolVersion,
  });

  final String cameraId;

  /// Device name shown to the user, e.g. "Google Pixel 7".
  final String name;

  /// IPv4 address.
  final String host;
  final int port;
  /// API version from the TXT `v`.
  final int version;

  /// Speaks our API version; others are listed but can't be picked.
  bool get compatible => version == protocolVersion;

  /// `http://host:port` in the form the Viewer stores (see `normalizeCameraAddress`).
  Uri get base => Uri(scheme: 'http', host: host, port: port);

  /// Builds one from a resolved service; null when it isn't one of our Cameras or has no
  /// usable address. [serviceName] stands in for a missing TXT name.
  static DiscoveredCamera? fromService({
    required String serviceName,
    required List<String> addresses,
    required int port,
    required Map<String, String> txt,
  }) {
    final cameraId = txt[NsdTxt.cameraId]?.trim() ?? '';
    final version = int.tryParse(txt[NsdTxt.version]?.trim() ?? '');
    final host = pickHostAddress(addresses);
    if (cameraId.isEmpty || version == null || host == null || port <= 0 || port > 65535) return null;
    final name = txt[NsdTxt.name]?.trim() ?? '';
    return DiscoveredCamera(
      cameraId: cameraId,
      name: name.isEmpty ? serviceName : name,
      host: host,
      port: port,
      version: version,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveredCamera &&
      other.cameraId == cameraId &&
      other.name == name &&
      other.host == host &&
      other.port == port &&
      other.version == version;

  @override
  int get hashCode => Object.hash(cameraId, name, host, port, version);

  @override
  String toString() => 'DiscoveredCamera($name, $cameraId, $host:$port, v$version)';
}

/// First IPv4 address: the Camera's server and the Viewer's stored addresses are IPv4 only.
String? pickHostAddress(List<String> addresses) {
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  for (final a in addresses) {
    final m = v4.firstMatch(a.trim());
    if (m != null && [1, 2, 3, 4].every((i) => int.parse(m.group(i)!) <= 255)) return a.trim();
  }
  return null;
}

/// Cameras currently seen, keyed by service name. A Camera announced on two interfaces (or
/// re-announced under a new name) shows once, by its install id.
@immutable
class DiscoveredCameras {
  const DiscoveredCameras([this._byService = const {}]);

  final Map<String, DiscoveredCamera> _byService;

  DiscoveredCameras resolved(String serviceName, DiscoveredCamera camera) =>
      DiscoveredCameras({..._byService, serviceName: camera});

  DiscoveredCameras lost(String serviceName) =>
      _byService.containsKey(serviceName) ? DiscoveredCameras({..._byService}..remove(serviceName)) : this;

  /// One entry per Camera, sorted by name.
  List<DiscoveredCamera> get list {
    final byId = <String, DiscoveredCamera>{};
    for (final c in _byService.values) {
      byId.putIfAbsent(c.cameraId, () => c);
    }
    return byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

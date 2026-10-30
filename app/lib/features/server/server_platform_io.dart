import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../../core/web_bundle.dart';
import '../discovery/nsd.dart';
import 'api_server.dart';
import 'camera_server.dart';

final serverPlatform = ServerPlatform(
  createServer: (config) async => CameraServer(
    capture: config.capture,
    secrets: config.secrets,
    cameraInfo: config.cameraInfo,
    webRoot: await extractWebBundle(),
  ),
  localAddress: localNetworkAddress,
  deviceName: _deviceName,
  announce: announceCamera,
);

/// The private IPv4 address viewers most likely reach us on: Wi-Fi or hotspot interfaces first,
/// then 192.168.x, 10.x and 172.16–31.x. Mobile data (often carrier 10.x) loses to Wi-Fi by name.
Future<String?> localNetworkAddress() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } catch (_) {
    return null;
  }
  final candidates = [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal) (name: i.name, address: a.address),
  ];
  return pickLocalAddress(candidates);
}

/// Picks from (interface name, IPv4) pairs; exposed for tests.
String? pickLocalAddress(List<({String name, String address})> candidates) {
  int rank(({String name, String address}) c) {
    final wireless = RegExp(r'^(wlan|swlan|ap|softap|wl|wifi|en)', caseSensitive: false).hasMatch(c.name);
    final parts = c.address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.contains(null)) return 1 << 20;
    final (a, b) = (parts[0]!, parts[1]!);
    final private = switch ((a, b)) {
      (192, 168) => 0,
      (10, _) => 1,
      (172, >= 16 && <= 31) => 2,
      _ => 10,
    };
    return private + (wireless ? 0 : 5);
  }

  if (candidates.isEmpty) return null;
  final sorted = [...candidates]..sort((x, y) => rank(x).compareTo(rank(y)));
  return sorted.first.address;
}

Future<String> _deviceName() async {
  try {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final maker = info.manufacturer.trim();
      final model = info.model.trim();
      if (model.isEmpty) return maker.isEmpty ? 'Android' : maker;
      // Prefix the maker unless the model already includes it.
      final named = maker.isEmpty || model.toLowerCase().startsWith(maker.toLowerCase()) ? model : '$maker $model';
      return named[0].toUpperCase() + named.substring(1);
    }
  } catch (_) {
    // Fall through to the host name.
  }
  return Platform.localHostname;
}

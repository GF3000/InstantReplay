import 'dart:io';

/// Resolves the stream server's host: on a hotspot or router without Internet this fails fast.
Future<bool> canReachStreamServer(String server) async {
  final host = Uri.tryParse(server)?.host;
  if (host == null || host.isEmpty) return false;
  if (host == 'localhost' || InternetAddress.tryParse(host) != null) return true;
  try {
    final found = await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
    return found.isNotEmpty;
  } catch (_) {
    return false;
  }
}

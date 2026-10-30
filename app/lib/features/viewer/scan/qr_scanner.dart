import 'package:flutter/widgets.dart';

import 'qr_scanner_none.dart' if (dart.library.io) 'qr_scanner_mobile.dart' as platform;

/// The in-app QR scanner of the native Viewer, behind an interface so tests can fake the camera.
///
/// The web build gets the no-op one: mobile_scanner's web side loads its decoder from a CDN, and
/// the web Viewer must not reach the Internet (SPEC §6).
abstract class QrScanner {
  factory QrScanner.platform() => platform.createQrScanner();

  /// Android with a camera.
  Future<bool> isAvailable();

  /// Asks for the camera permission; false when denied.
  Future<bool> requestPermission();

  /// Live camera preview that reports the text of every QR it reads.
  Widget preview({required ValueChanged<String> onCode});
}

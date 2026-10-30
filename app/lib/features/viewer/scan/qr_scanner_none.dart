import 'package:flutter/widgets.dart';

import 'qr_scanner.dart';

QrScanner createQrScanner() => const _NoQrScanner();

class _NoQrScanner implements QrScanner {
  const _NoQrScanner();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Widget preview({required ValueChanged<String> onCode}) => const SizedBox.shrink();
}

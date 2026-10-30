import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'qr_scanner.dart';

const _channel = MethodChannel('instant_replay/device');

QrScanner createQrScanner() => const _MobileQrScanner();

class _MobileQrScanner implements QrScanner {
  const _MobileQrScanner();

  @override
  Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('hasCamera') ?? false;
    } on PlatformException catch (e) {
      debugPrint('hasCamera failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async => (await Permission.camera.request()).isGranted;

  @override
  Widget preview({required ValueChanged<String> onCode}) => _ScannerPreview(onCode: onCode);
}

class _ScannerPreview extends StatefulWidget {
  const _ScannerPreview({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_ScannerPreview> createState() => _ScannerPreviewState();
}

class _ScannerPreviewState extends State<_ScannerPreview> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          for (final code in capture.barcodes) {
            if (code.rawValue case final text?) widget.onCode(text);
          }
        },
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../data/viewer_api.dart';
import 'qr_scanner.dart';

final qrScannerProvider = Provider<QrScanner>((_) => QrScanner.platform());

/// Whether to offer "Scan QR": Android with a camera.
final qrScannerAvailableProvider = FutureProvider<bool>((ref) => ref.watch(qrScannerProvider).isAvailable());

/// Full-screen scanner that pops with the first Camera link it reads. Other QR codes show an
/// error and scanning goes on.
class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});

  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage> {
  bool _done = false;
  bool _wrongCode = false;

  void _onCode(String text) {
    if (_done) return;
    final link = parseScannedCameraLink(text);
    if (link == null) {
      if (!_wrongCode) setState(() => _wrongCode = true);
      return;
    }
    _done = true;
    Navigator.of(context).pop(link);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(l10n.viewerScanQr)),
      body: Stack(fit: StackFit.expand, children: [
        ref.watch(qrScannerProvider).preview(onCode: _onCode),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Card(
            key: const ValueKey('viewer-scan-message'),
            color: _wrongCode ? theme.colorScheme.errorContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _wrongCode ? l10n.viewerScanNotCamera : l10n.viewerScanHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _wrongCode ? theme.colorScheme.onErrorContainer : null,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

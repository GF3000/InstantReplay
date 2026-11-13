import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ir_colors.dart';
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
    final c = context.ir;
    final accent = _wrongCode ? c.live : c.signal;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(l10n.viewerScanQr)),
      body: Stack(fit: StackFit.expand, children: [
        ref.watch(qrScannerProvider).preview(onCode: _onCode),
        // Viewfinder: the area outside the frame dimmed, amber corners (red after a foreign QR).
        IgnorePointer(child: CustomPaint(painter: _ViewfinderPainter(corner: accent))),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  key: const ValueKey('viewer-scan-message'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _wrongCode ? c.liveSoft : c.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _wrongCode ? c.live : c.lineStrong),
                  ),
                  child: Row(children: [
                    Icon(_wrongCode ? Icons.error_outline : Icons.qr_code_2, color: _wrongCode ? c.liveText : c.signal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _wrongCode ? l10n.viewerScanNotCamera : l10n.viewerScanHint,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _wrongCode ? c.liveText : c.text,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.corner});

  final Color corner;

  @override
  void paint(Canvas canvas, Size size) {
    // A square frame a little above the centre, clear of the hint panel.
    final side = math.min(size.width, size.height) * 0.62;
    final center = Offset(size.width / 2, size.height * 0.44);
    final frame = Rect.fromCenter(center: center, width: side, height: side);
    final hole = RRect.fromRectAndRadius(frame, const Radius.circular(8));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    final arm = side * 0.16;
    final paint = Paint()
      ..color = corner
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;
    for (final (x, y, dx, dy) in [
      (frame.left, frame.top, 1.0, 1.0),
      (frame.right, frame.top, -1.0, 1.0),
      (frame.left, frame.bottom, 1.0, -1.0),
      (frame.right, frame.bottom, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(Offset(x, y), Offset(x + dx * arm, y), paint)
        ..drawLine(Offset(x, y), Offset(x, y + dy * arm), paint);
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) => oldDelegate.corner != corner;
}

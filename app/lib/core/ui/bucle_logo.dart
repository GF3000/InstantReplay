import 'package:flutter/material.dart';

/// The app mark ("Bucle": a loop arrow around a ball) drawn from the paths of
/// `app/branding/icon_legacy.svg`, so no SVG package or asset is needed.
///
/// The brand colours are fixed on purpose: the mark looks the same in both themes.
class BucleLogo extends StatelessWidget {
  const BucleLogo({super.key, this.size = 48, this.semanticLabel});

  final double size;

  /// Null hides it from screen readers (decorative next to the app name).
  final String? semanticLabel;

  /// Brand amber and ink of the launcher icon.
  static const amber = Color(0xFFFFC107);
  static const ink = Color(0xFF15120A);

  @override
  Widget build(BuildContext context) {
    final logo = SizedBox.square(dimension: size, child: const CustomPaint(painter: _BuclePainter()));
    return semanticLabel == null ? ExcludeSemantics(child: logo) : Semantics(label: semanticLabel, image: true, child: logo);
  }
}

class _BuclePainter extends CustomPainter {
  const _BuclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // SVG viewBox "18 18 72 72".
    final scale = size.shortestSide / 72;
    canvas
      ..save()
      ..scale(scale)
      ..translate(-18, -18);

    final squircle = Path()
      ..moveTo(54, 18)
      ..cubicTo(80, 18, 90, 28, 90, 54)
      ..cubicTo(90, 80, 80, 90, 54, 90)
      ..cubicTo(28, 90, 18, 80, 18, 54)
      ..cubicTo(18, 28, 28, 18, 54, 18)
      ..close();
    canvas.drawPath(squircle, Paint()..color = BucleLogo.amber);

    final ink = Paint()..color = BucleLogo.ink;
    // Loop: "M34.95 43 A22 22 0 1 0 54 32".
    final loop = Path()
      ..moveTo(34.95, 43)
      ..arcToPoint(const Offset(54, 32), radius: const Radius.circular(22), largeArc: true, clockwise: false);
    canvas.drawPath(
      loop,
      Paint()
        ..color = BucleLogo.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );

    // Arrow head.
    final head = Path()
      ..moveTo(42.8, 32)
      ..lineTo(56.45, 22.55)
      ..lineTo(56.45, 41.45)
      ..close();
    canvas
      ..drawPath(head, ink)
      ..drawPath(
        head,
        Paint()
          ..color = BucleLogo.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );

    // Ball with its seams.
    canvas.drawCircle(const Offset(54, 54), 10, ink);
    final seam = Paint()
      ..color = BucleLogo.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(54, 44.5), const Offset(54, 63.5), seam)
      ..drawPath(
        Path()
          ..moveTo(47, 47.5)
          ..quadraticBezierTo(51.5, 54, 47, 60.5),
        seam,
      )
      ..drawPath(
        Path()
          ..moveTo(61, 47.5)
          ..quadraticBezierTo(56.5, 54, 61, 60.5),
        seam,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BuclePainter oldDelegate) => false;
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Where the arrow and the circle of the telestrator shot go, as fractions of the frame. They
/// match the generated pitch; with your own photos in `marketing/frames/`, move them onto your
/// players.
const keyPlayer = Offset(0.40, 0.62);
const runTarget = Offset(0.68, 0.40);
const markedPlayer = Offset(0.73, 0.55);

/// A stand-in match frame (stands, a mown pitch in perspective, two teams) for when there are no
/// photos in `marketing/frames/`. Each [seed] moves the players, so thumbnails differ.
class PitchPainter extends CustomPainter {
  const PitchPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.24;

    // Stands: a dark gradient full of tiny spectators.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, horizon),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, horizon), [const Color(0xFF1B2230), const Color(0xFF2E3644)]),
    );
    final crowd = math.Random(7);
    final dot = Paint();
    for (var i = 0; i < 2600; i++) {
      final y = crowd.nextDouble() * (horizon - h * 0.03);
      dot.color = HSLColor.fromAHSL(1, crowd.nextDouble() * 360, 0.35, 0.25 + crowd.nextDouble() * 0.35).toColor();
      canvas.drawCircle(Offset(crowd.nextDouble() * w, y), w * 0.0016 * (0.6 + y / horizon), dot);
    }
    // Advertising boards.
    final boards = Rect.fromLTWH(0, horizon - h * 0.03, w, h * 0.03);
    canvas.drawRect(boards, Paint()..color = const Color(0xFF0D47A1));
    for (var x = 0.0; x < w; x += w / 6) {
      canvas.drawRect(Rect.fromLTWH(x + w * 0.02, boards.top + boards.height * 0.3, w / 10, boards.height * 0.4),
          Paint()..color = Colors.white.withValues(alpha: 0.75));
    }

    // Grass: perspective stripes.
    Offset p(double fx, double fy) {
      // fx 0..1 across the pitch, fy 0 (far) .. 1 (near); the near edge is wider than the frame.
      final y = horizon + (h - horizon) * fy;
      final spread = 0.62 + 0.9 * fy;
      return Offset(w * (0.5 + (fx - 0.5) * spread), y);
    }

    for (var i = 0; i < 10; i++) {
      final a = i / 10, b = (i + 1) / 10;
      final path = Path()
        ..moveTo(p(-0.5, a).dx, p(0, a).dy)
        ..lineTo(p(1.5, a).dx, p(0, a).dy)
        ..lineTo(p(1.5, b).dx, p(0, b).dy)
        ..lineTo(p(-0.5, b).dx, p(0, b).dy)
        ..close();
      canvas.drawPath(path, Paint()..color = i.isEven ? const Color(0xFF2E7D32) : const Color(0xFF388E3C));
    }
    // Soft light from above.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()
        ..shader = ui.Gradient.radial(Offset(w * 0.5, h * 0.35), w * 0.8,
            [Colors.white.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.25)]),
    );

    // Lines: touchline, halfway line, centre circle.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.003;
    canvas.drawPath(
        Path()
          ..moveTo(p(0, 0.04).dx, p(0, 0.04).dy)
          ..lineTo(p(1, 0.04).dx, p(1, 0.04).dy),
        line);
    canvas.drawLine(p(0.5, 0.04), p(0.5, 1.2), line);
    final c = p(0.5, 0.45);
    canvas.drawOval(Rect.fromCenter(center: c, width: w * 0.30, height: h * 0.20), line);
    canvas.drawCircle(c, w * 0.004, Paint()..color = Colors.white);

    // Players, far ones first so near ones overlap them.
    final rnd = math.Random(seed);
    final players = <(Offset, Color, Color)>[
      for (var i = 0; i < 9; i++)
        (Offset(0.08 + rnd.nextDouble() * 0.84, 0.32 + rnd.nextDouble() * 0.6), const Color(0xFFD32F2F), Colors.white),
      for (var i = 0; i < 9; i++)
        (Offset(0.08 + rnd.nextDouble() * 0.84, 0.32 + rnd.nextDouble() * 0.6), const Color(0xFFFDD835), const Color(0xFF1A237E)),
      // The two the telestrator shot marks.
      (keyPlayer, const Color(0xFFD32F2F), Colors.white),
      (markedPlayer, const Color(0xFFFDD835), const Color(0xFF1A237E)),
    ]..sort((a, b) => a.$1.dy.compareTo(b.$1.dy));
    for (final (at, shirt, shorts) in players) {
      _player(canvas, Offset(at.dx * w, at.dy * h), h * (0.07 + 0.11 * at.dy), shirt, shorts);
    }
    // The ball, at the key player's feet.
    final ball = Offset(keyPlayer.dx * w + h * 0.03, keyPlayer.dy * h + h * 0.005);
    canvas.drawCircle(ball + Offset(h * 0.006, h * 0.004), h * 0.011, Paint()..color = Colors.black26);
    canvas.drawCircle(ball, h * 0.011, Paint()..color = Colors.white);
  }

  /// A simple figure standing at [feet], [height] tall.
  void _player(Canvas canvas, Offset feet, double height, Color shirt, Color shorts) {
    final u = height / 10;
    canvas.drawOval(Rect.fromCenter(center: feet + Offset(u * 0.8, 0), width: u * 5, height: u * 1.1),
        Paint()..color = Colors.black.withValues(alpha: 0.30));
    final legs = Paint()
      ..color = const Color(0xFFE0B48A)
      ..strokeWidth = u * 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(feet + Offset(-u * 0.7, -u * 0.3), feet + Offset(-u * 0.5, -u * 3.6), legs);
    canvas.drawLine(feet + Offset(u * 0.7, -u * 0.3), feet + Offset(u * 0.5, -u * 3.6), legs);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(feet.dx - u * 1.3, feet.dy - u * 5, u * 2.6, u * 1.8), Radius.circular(u * 0.4)),
        Paint()..color = shorts);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(feet.dx - u * 1.5, feet.dy - u * 8.2, u * 3, u * 3.5), Radius.circular(u * 0.8)),
        Paint()..color = shirt);
    canvas.drawCircle(feet + Offset(0, -u * 9.1), u * 0.95, Paint()..color = const Color(0xFFD7A57C));
  }

  @override
  bool shouldRepaint(PitchPainter old) => old.seed != seed;
}

/// [PitchPainter] as PNG bytes, [width] × 9/16.
Future<List<int>> renderPitchPng(int seed, {double width = 1280}) async {
  final size = Size(width, width * 9 / 16);
  final recorder = ui.PictureRecorder();
  PitchPainter(seed).paint(Canvas(recorder), size);
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

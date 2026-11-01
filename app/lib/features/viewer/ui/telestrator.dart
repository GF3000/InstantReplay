import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// One freehand line. Points are fractions of the video's width and height, so a stroke stays on
/// the same spot of the picture when the screen rotates or the layout changes.
@immutable
class TelestratorStroke {
  const TelestratorStroke(this.color, this.points);

  final Color color;
  final List<Offset> points;
}

/// The drawing on the paused frame (simple telestrator, v0.3.3): not saved and not exported, gone
/// when the review leaves draw mode.
class TelestratorController extends ChangeNotifier {
  /// Readable on grass, courts and dark kit.
  static const colors = [Color(0xFFE53935), Color(0xFFFFEB3B), Colors.white, Color(0xFF2196F3), Colors.black];

  final List<TelestratorStroke> _strokes = [];
  Color _color = colors.first;

  List<TelestratorStroke> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.isEmpty;
  Color get color => _color;

  set color(Color c) {
    _color = c;
    notifyListeners();
  }

  void begin(Offset point) {
    _strokes.add(TelestratorStroke(_color, [point]));
    notifyListeners();
  }

  void extend(Offset point) {
    if (_strokes.isEmpty) return;
    _strokes.last.points.add(point);
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }
}

/// Draws [controller]'s strokes over the video and, when [enabled], adds new ones with a finger.
/// Sized to the video itself (inside its AspectRatio).
class TelestratorCanvas extends StatelessWidget {
  const TelestratorCanvas({super.key, required this.controller, required this.enabled});

  final TelestratorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      Offset rel(Offset p) => Offset((p.dx / size.width).clamp(0, 1), (p.dy / size.height).clamp(0, 1));
      return GestureDetector(
        key: const ValueKey('review-canvas'),
        behavior: enabled ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onPanStart: enabled ? (d) => controller.begin(rel(d.localPosition)) : null,
        onPanUpdate: enabled ? (d) => controller.extend(rel(d.localPosition)) : null,
        child: CustomPaint(painter: _StrokePainter(controller), size: size),
      );
    },
  );
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.controller) : super(repaint: controller);

  final TelestratorController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final width = (size.shortestSide * 0.012).clamp(3.0, 8.0);
    for (final s in controller.strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final pts = [for (final p in s.points) Offset(p.dx * size.width, p.dy * size.height)];
      if (pts.length == 1) {
        canvas.drawCircle(pts.single, width / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

/// Colour swatches, Undo, Clear and Done for draw mode.
class TelestratorToolbar extends StatelessWidget {
  const TelestratorToolbar({super.key, required this.controller, required this.onDone});

  final TelestratorController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            for (final (i, c) in TelestratorController.colors.indexed)
              IconButton(
                key: ValueKey('draw-color-$i'),
                tooltip: l10n.viewerDrawColor,
                isSelected: controller.color == c,
                onPressed: () => controller.color = c,
                icon: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: controller.color == c ? Theme.of(context).colorScheme.primary : Colors.grey,
                      width: controller.color == c ? 3 : 1,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.viewerDrawUndo,
              onPressed: controller.isEmpty ? null : controller.undo,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: l10n.viewerDrawClear,
              onPressed: controller.isEmpty ? null : controller.clear,
              icon: const Icon(Icons.layers_clear),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('draw-done'),
              onPressed: onDone,
              icon: const Icon(Icons.check),
              label: Text(l10n.viewerDrawDone),
            ),
          ],
        ),
      ),
    );
  }
}

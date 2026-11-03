import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// What a drag draws: a freehand line, or a straight line, arrow or ellipse from where the finger
/// went down to where it is.
enum TelestratorTool { pen, line, arrow, circle }

/// One mark. Points are fractions of the video's width and height, so a mark stays on the same
/// spot of the picture when the screen rotates or the layout changes. Shapes keep two points:
/// start and end (the ellipse fits the box between them).
class TelestratorStroke {
  TelestratorStroke(this.color, this.points, {this.tool = TelestratorTool.pen, this.thick = false});

  final Color color;
  final TelestratorTool tool;
  final bool thick;
  final List<Offset> points;
}

/// The drawing on the paused frame (simple telestrator, v0.3.3): not saved and not exported, gone
/// when the review leaves draw mode.
class TelestratorController extends ChangeNotifier {
  /// Readable on grass, courts and dark kit.
  static const colors = [Color(0xFFE53935), Color(0xFFFFEB3B), Colors.white, Color(0xFF2196F3), Colors.black];

  final List<TelestratorStroke> _strokes = [];
  Color _color = colors.first;
  TelestratorTool _tool = TelestratorTool.arrow;
  bool _thick = false;

  List<TelestratorStroke> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.isEmpty;
  Color get color => _color;
  TelestratorTool get tool => _tool;
  bool get thick => _thick;

  set color(Color c) {
    _color = c;
    notifyListeners();
  }

  set tool(TelestratorTool t) {
    _tool = t;
    notifyListeners();
  }

  set thick(bool v) {
    _thick = v;
    notifyListeners();
  }

  void begin(Offset point) {
    _strokes.add(TelestratorStroke(_color, [point], tool: _tool, thick: _thick));
    notifyListeners();
  }

  void extend(Offset point) {
    if (_strokes.isEmpty) return;
    final points = _strokes.last.points;
    if (_strokes.last.tool == TelestratorTool.pen || points.length < 2) {
      points.add(point);
    } else {
      points.last = point;
    }
    notifyListeners();
  }

  /// The finger lifted: a shape that never got a size is dropped.
  void end() {
    if (_strokes.isEmpty) return;
    final last = _strokes.last;
    if (last.tool != TelestratorTool.pen && (last.points.length < 2 || last.points.first == last.points.last)) {
      _strokes.removeLast();
      notifyListeners();
    }
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
        onPanEnd: enabled ? (_) => controller.end() : null,
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
    final thin = (size.shortestSide * 0.012).clamp(3.0, 8.0);
    for (final s in controller.strokes) {
      final width = s.thick ? thin * 2 : thin;
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
      switch (s.tool) {
        case TelestratorTool.pen:
          final path = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (final p in pts.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
        case TelestratorTool.line:
          canvas.drawLine(pts.first, pts.last, paint);
        case TelestratorTool.arrow:
          canvas.drawLine(pts.first, pts.last, paint);
          _arrowHead(canvas, pts.first, pts.last, width, paint);
        case TelestratorTool.circle:
          canvas.drawOval(Rect.fromPoints(pts.first, pts.last), paint);
      }
    }
  }

  /// Two barbs at [to], pointing back along the line from [from].
  static void _arrowHead(Canvas canvas, Offset from, Offset to, double width, Paint paint) {
    final d = to - from;
    if (d.distance == 0) return;
    final length = math.max(width * 4, 16.0);
    final angle = math.atan2(d.dy, d.dx);
    for (final side in const [-1, 1]) {
      final a = angle + math.pi + side * math.pi / 7;
      canvas.drawLine(to, to + Offset(math.cos(a), math.sin(a)) * length, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

/// Tools, thickness, colour swatches, Undo, Clear and Done for draw mode.
class TelestratorToolbar extends StatelessWidget {
  const TelestratorToolbar({super.key, required this.controller, required this.onDone});

  final TelestratorController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Compact buttons: two rows at most on a phone held upright, one on a tablet.
    return IconButtonTheme(
      data: const IconButtonThemeData(style: ButtonStyle(visualDensity: VisualDensity.compact)),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              for (final (tool, icon, tooltip) in [
                (TelestratorTool.arrow, Icons.north_east, l10n.viewerDrawArrow),
                (TelestratorTool.circle, Icons.circle_outlined, l10n.viewerDrawCircle),
                (TelestratorTool.line, Icons.horizontal_rule, l10n.viewerDrawLine),
                (TelestratorTool.pen, Icons.gesture, l10n.viewerDrawPen),
              ])
                IconButton(
                  key: ValueKey('draw-tool-${tool.name}'),
                  tooltip: tooltip,
                  isSelected: controller.tool == tool,
                  style: IconButton.styleFrom(
                    backgroundColor: controller.tool == tool ? Theme.of(context).colorScheme.secondaryContainer : null,
                  ),
                  onPressed: () => controller.tool = tool,
                  icon: Icon(icon),
                ),
              IconButton(
                key: const ValueKey('draw-thick'),
                tooltip: l10n.viewerDrawThick,
                isSelected: controller.thick,
                style: IconButton.styleFrom(
                  backgroundColor: controller.thick ? Theme.of(context).colorScheme.secondaryContainer : null,
                ),
                onPressed: () => controller.thick = !controller.thick,
                icon: const Icon(Icons.line_weight),
              ),
              const SizedBox(width: 8),
              for (final (i, c) in TelestratorController.colors.indexed)
                IconButton(
                  key: ValueKey('draw-color-$i'),
                  tooltip: l10n.viewerDrawColor,
                  isSelected: controller.color == c,
                  onPressed: () => controller.color = c,
                  icon: Container(
                    width: 24,
                    height: 24,
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
      ),
    );
  }
}

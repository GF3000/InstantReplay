import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// What a drag does: draws a freehand line, or a straight line, arrow or ellipse from where the
/// finger went down to where it is; or, with [select], picks a mark and moves it; with [eraser],
/// removes the marks it touches.
enum TelestratorTool {
  pen,
  line,
  arrow,
  circle,
  select,
  eraser;

  bool get draws => this != select && this != eraser;
}

/// One mark. Points are fractions of the video's width and height, so a mark stays on the same
/// spot of the picture when the screen rotates or the layout changes. Shapes keep two points:
/// start and end (the ellipse fits the box between them).
class TelestratorStroke {
  TelestratorStroke(this.color, this.points, {this.tool = TelestratorTool.pen, this.thick = false});

  Color color;
  final TelestratorTool tool;
  bool thick;
  final List<Offset> points;

  TelestratorStroke copy() => TelestratorStroke(color, [...points], tool: tool, thick: thick);
}

/// The drawing on the paused frame (simple telestrator, v0.3.3): not saved and not exported, gone
/// when the review leaves draw mode.
class TelestratorController extends ChangeNotifier {
  /// Readable on grass, courts and dark kit.
  static const colors = [Color(0xFFE53935), Color(0xFFFFEB3B), Colors.white, Color(0xFF2196F3), Colors.black];

  final List<TelestratorStroke> _strokes = [];

  /// What Undo goes back to: the marks before each change (a new mark, a move, a delete, ...).
  final List<List<TelestratorStroke>> _history = [];
  Color _color = colors.first;
  TelestratorTool _tool = TelestratorTool.arrow;
  bool _thick = false;
  TelestratorStroke? _selected;
  bool _erased = false;

  List<TelestratorStroke> get strokes => List.unmodifiable(_strokes);
  bool get isEmpty => _strokes.isEmpty;
  bool get canUndo => _history.isNotEmpty;
  Color get color => _color;
  TelestratorTool get tool => _tool;
  bool get thick => _thick;

  /// The mark picked with [TelestratorTool.select]: colour and thickness apply to it.
  TelestratorStroke? get selected => _selected;

  set color(Color c) {
    _color = c;
    if (_selected case final s? when s.color != c) {
      _save();
      s.color = c;
    }
    notifyListeners();
  }

  set tool(TelestratorTool t) {
    _tool = t;
    if (t != TelestratorTool.select) _selected = null;
    notifyListeners();
  }

  set thick(bool v) {
    _thick = v;
    if (_selected case final s? when s.thick != v) {
      _save();
      s.thick = v;
    }
    notifyListeners();
  }

  void _save() => _history.add([for (final s in _strokes) s.copy()]);

  void begin(Offset point) {
    _save();
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
      _history.removeLast();
      notifyListeners();
    }
  }

  /// The topmost mark within reach of [point] (a fraction of [size], like the marks' points).
  TelestratorStroke? hit(Offset point, Size size) {
    final p = Offset(point.dx * size.width, point.dy * size.height);
    for (final s in _strokes.reversed) {
      final pts = [for (final q in s.points) Offset(q.dx * size.width, q.dy * size.height)];
      final outline = switch (s.tool) {
        TelestratorTool.circle when pts.length > 1 => _ellipse(Rect.fromPoints(pts.first, pts.last)),
        _ => pts,
      };
      // Generous: a finger is wide and a thin arrow is easy to miss.
      if (_distance(p, outline) <= math.max(24, strokeWidth(size, thick: s.thick))) return s;
    }
    return null;
  }

  /// Selects the mark at [point], or nothing; true when there was one. The colour and thickness
  /// buttons then show (and change) that mark's.
  bool select(Offset point, Size size) {
    _selected = hit(point, size);
    if (_selected case final s?) {
      _color = s.color;
      _thick = s.thick;
    }
    notifyListeners();
    return _selected != null;
  }

  /// Moves the selected mark by [delta] (a fraction of the video's size). [first] starts a move,
  /// which Undo takes back in one go.
  void moveSelected(Offset delta, {bool first = false}) {
    final s = _selected;
    if (s == null) return;
    if (first) _save();
    for (var i = 0; i < s.points.length; i++) {
      s.points[i] += delta;
    }
    notifyListeners();
  }

  /// Removes the mark at [point], if any. [first] starts an eraser drag: Undo brings back
  /// everything that drag removed.
  void eraseAt(Offset point, Size size, {bool first = false}) {
    if (first) _erased = false;
    final s = hit(point, size);
    if (s == null) return;
    if (!_erased) _save();
    _erased = true;
    _strokes.remove(s);
    if (identical(s, _selected)) _selected = null;
    notifyListeners();
  }

  void deleteSelected() {
    final s = _selected;
    if (s == null) return;
    _save();
    _strokes.remove(s);
    _selected = null;
    notifyListeners();
  }

  void undo() {
    if (_history.isEmpty) return;
    _strokes
      ..clear()
      ..addAll(_history.removeLast());
    _selected = null;
    notifyListeners();
  }

  /// Removes every mark; Undo brings them back.
  void clear() {
    if (_strokes.isEmpty) return;
    _save();
    _strokes.clear();
    _selected = null;
    notifyListeners();
  }

  /// Back to an empty drawing with nothing to undo (draw mode ended).
  void reset() {
    _strokes.clear();
    _history.clear();
    _selected = null;
    notifyListeners();
  }

  /// Line width on a video [size] pixels big.
  static double strokeWidth(Size size, {required bool thick}) {
    final thin = (size.shortestSide * 0.012).clamp(3.0, 8.0);
    return thick ? thin * 2 : thin;
  }

  static List<Offset> _ellipse(Rect r) => [
    for (var i = 0; i <= 48; i++)
      r.center + Offset(math.cos(i * math.pi / 24) * r.width / 2, math.sin(i * math.pi / 24) * r.height / 2),
  ];

  /// From [p] to the nearest point of the polyline [pts].
  static double _distance(Offset p, List<Offset> pts) {
    if (pts.isEmpty) return double.infinity;
    var best = (p - pts.first).distance;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], ab = pts[i] - a;
      final len2 = ab.distanceSquared;
      final t = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      best = math.min(best, (p - (a + ab * t)).distance);
    }
    return best;
  }
}

/// Draws [controller]'s strokes over the video and, when [enabled], works on them with a finger:
/// draws, selects and moves, or erases (by tool); a double tap removes a mark with any tool.
/// Sized to the video itself (inside its AspectRatio).
class TelestratorCanvas extends StatefulWidget {
  const TelestratorCanvas({super.key, required this.controller, required this.enabled});

  final TelestratorController controller;
  final bool enabled;

  @override
  State<TelestratorCanvas> createState() => _TelestratorCanvasState();
}

class _TelestratorCanvasState extends State<TelestratorCanvas> {
  /// A select drag that started on a mark: it carries it.
  bool _moving = false;
  Offset? _doubleTapAt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final c = widget.controller;
      final size = box.biggest;
      final paint = CustomPaint(painter: _StrokePainter(c), size: size);
      if (!widget.enabled) return paint;
      Offset rel(Offset p) => Offset((p.dx / size.width).clamp(0, 1), (p.dy / size.height).clamp(0, 1));
      return GestureDetector(
        key: const ValueKey('review-canvas'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          final p = rel(d.localPosition);
          switch (c.tool) {
            case TelestratorTool.select:
              _moving = c.select(p, size);
              if (_moving) c.moveSelected(Offset.zero, first: true);
            case TelestratorTool.eraser:
              c.eraseAt(p, size, first: true);
            case _:
              c.begin(p);
          }
        },
        onPanUpdate: (d) {
          switch (c.tool) {
            case TelestratorTool.select:
              if (_moving) c.moveSelected(Offset(d.delta.dx / size.width, d.delta.dy / size.height));
            case TelestratorTool.eraser:
              c.eraseAt(rel(d.localPosition), size);
            case _:
              c.extend(rel(d.localPosition));
          }
        },
        onPanEnd: (_) {
          _moving = false;
          if (c.tool.draws) c.end();
        },
        onTapUp: (d) {
          if (c.tool == TelestratorTool.select) c.select(rel(d.localPosition), size);
          if (c.tool == TelestratorTool.eraser) c.eraseAt(rel(d.localPosition), size, first: true);
        },
        onDoubleTapDown: (d) => _doubleTapAt = rel(d.localPosition),
        onDoubleTap: () {
          if (_doubleTapAt case final p?) c.eraseAt(p, size, first: true);
        },
        child: paint,
      );
    },
  );
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.controller) : super(repaint: controller);

  final TelestratorController controller;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in controller.strokes) {
      final width = TelestratorController.strokeWidth(size, thick: s.thick);
      final pts = [for (final p in s.points) Offset(p.dx * size.width, p.dy * size.height)];
      // The selected mark sits on a halo that stands out from its own colour.
      if (identical(s, controller.selected)) {
        final halo = s.color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
        _mark(canvas, s.tool, pts, width + 10, halo.withValues(alpha: 0.6));
      }
      _mark(canvas, s.tool, pts, width, s.color);
    }
  }

  static void _mark(Canvas canvas, TelestratorTool tool, List<Offset> pts, double width, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (pts.length == 1) {
      canvas.drawCircle(pts.single, width / 2, paint..style = PaintingStyle.fill);
      return;
    }
    switch (tool) {
      case TelestratorTool.line:
        canvas.drawLine(pts.first, pts.last, paint);
      case TelestratorTool.arrow:
        canvas.drawLine(pts.first, pts.last, paint);
        _arrowHead(canvas, pts.first, pts.last, width, paint);
      case TelestratorTool.circle:
        canvas.drawOval(Rect.fromPoints(pts.first, pts.last), paint);
      case _:
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
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

/// Tools, thickness, colour swatches, Delete (with a mark selected), Undo, Clear and Done for draw
/// mode.
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
                (TelestratorTool.select, Icons.pan_tool_alt, l10n.viewerDrawSelect),
                (TelestratorTool.arrow, Icons.north_east, l10n.viewerDrawArrow),
                (TelestratorTool.circle, Icons.circle_outlined, l10n.viewerDrawCircle),
                (TelestratorTool.line, Icons.horizontal_rule, l10n.viewerDrawLine),
                (TelestratorTool.pen, Icons.gesture, l10n.viewerDrawPen),
                (TelestratorTool.eraser, Icons.auto_fix_normal, l10n.viewerDrawEraser),
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
              IconButton(
                tooltip: l10n.viewerDrawUndo,
                onPressed: controller.canUndo ? controller.undo : null,
                icon: const Icon(Icons.undo),
              ),
              // With a mark selected, Delete takes Clear's place: the toolbar keeps its rows.
              if (controller.selected != null)
                IconButton(
                  key: const ValueKey('draw-delete'),
                  tooltip: l10n.viewerDrawDelete,
                  onPressed: controller.deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                )
              else
                IconButton(
                  tooltip: l10n.viewerDrawClear,
                  onPressed: controller.isEmpty ? null : controller.clear,
                  icon: const Icon(Icons.layers_clear),
                ),
              IconButton.filledTonal(
                key: const ValueKey('draw-done'),
                tooltip: l10n.viewerDrawDone,
                onPressed: onDone,
                icon: const Icon(Icons.check),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

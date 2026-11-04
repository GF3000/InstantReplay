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
/// start and end (the ellipse fits the box between them, turned by [angle] about its centre).
class TelestratorStroke {
  TelestratorStroke(this.color, this.points, {this.tool = TelestratorTool.pen, this.thick = false, this.angle = 0});

  Color color;
  final TelestratorTool tool;
  bool thick;
  final List<Offset> points;

  /// Radians, clockwise on screen; ellipses only (other marks turn their points).
  double angle;

  TelestratorStroke copy() => TelestratorStroke(color, [...points], tool: tool, thick: thick, angle: angle);
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

  /// The mark being drawn is dropped (a second finger turned the drag into a pinch).
  void cancel() {
    if (_strokes.isEmpty || _history.isEmpty) return;
    _strokes.removeLast();
    _history.removeLast();
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
        TelestratorTool.circle when pts.length > 1 => _ellipse(s, size),
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

  /// The selected mark's handles (pixels on a video [size] big): both ends of a line or arrow, the
  /// corner of an ellipse's box; none for a freehand line.
  List<Offset> handles(Size size) {
    final s = _selected;
    if (s == null || s.points.length < 2) return const [];
    return switch (s.tool) {
      TelestratorTool.line || TelestratorTool.arrow => [_px(s.points.first, size), _px(s.points.last, size)],
      TelestratorTool.circle => [_box(s, size).corner],
      _ => const [],
    };
  }

  /// The handle within reach of [point] (a fraction of [size]), as an index into [handles].
  int? handleAt(Offset point, Size size) {
    final p = _px(point, size);
    final hs = handles(size);
    for (var i = hs.length - 1; i >= 0; i--) {
      if ((hs[i] - p).distance <= 24) return i;
    }
    return null;
  }

  /// Drags handle [index] of the selected mark to [point]: a line or arrow end goes there; an
  /// ellipse's corner goes there with the opposite corner kept in place. [first] starts the drag.
  void dragHandle(int index, Offset point, Size size, {bool first = false}) {
    final s = _selected;
    if (s == null || s.points.length < 2) return;
    if (first) _save();
    if (s.tool == TelestratorTool.circle) {
      final b = _box(s, size);
      final fixed = b.center * 2 - b.corner;
      final q = _px(point, size);
      final center = (fixed + q) / 2;
      final half = _turn((q - fixed) / 2, -s.angle);
      _setBox(s, center, half, size);
    } else if (index == 0) {
      s.points.first = point;
    } else {
      s.points.last = point;
    }
    notifyListeners();
  }

  /// Pinch on the selected mark: the fingers moved from [from] to [to] (fractions of [size]), [scale]
  /// times further apart and turned by [rotation] radians since the last update. [first] starts it.
  void transformSelected(Offset from, Offset to, double scale, double rotation, Size size, {bool first = false}) {
    final s = _selected;
    if (s == null) return;
    if (first) _save();
    final f0 = _px(from, size), f1 = _px(to, size);
    Offset map(Offset px) => f1 + _turn(px - f0, rotation) * scale;
    if (s.tool == TelestratorTool.circle && s.points.length > 1) {
      final b = _box(s, size);
      s.angle += rotation;
      _setBox(s, map(b.center), b.half * scale, size);
    } else {
      for (var i = 0; i < s.points.length; i++) {
        s.points[i] = _rel(map(_px(s.points[i], size)), size);
      }
    }
    notifyListeners();
  }

  static Offset _px(Offset rel, Size size) => Offset(rel.dx * size.width, rel.dy * size.height);
  static Offset _rel(Offset px, Size size) => Offset(px.dx / size.width, px.dy / size.height);
  static Offset _turn(Offset v, double a) =>
      Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));

  /// An ellipse's box in pixels: centre, half size before turning, and the end corner after it.
  static ({Offset center, Offset half, Offset corner}) _box(TelestratorStroke s, Size size) {
    final a = _px(s.points.first, size), b = _px(s.points.last, size);
    final center = (a + b) / 2, half = (b - a) / 2;
    return (center: center, half: half, corner: center + _turn(half, s.angle));
  }

  static void _setBox(TelestratorStroke s, Offset center, Offset half, Size size) {
    s.points
      ..first = _rel(center - half, size)
      ..last = _rel(center + half, size);
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

  static List<Offset> _ellipse(TelestratorStroke s, Size size) {
    final b = _box(s, size);
    return [
      for (var i = 0; i <= 48; i++)
        b.center +
            _turn(Offset(math.cos(i * math.pi / 24) * b.half.dx, math.sin(i * math.pi / 24) * b.half.dy), s.angle),
    ];
  }

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
/// draws, selects and moves (or drags a handle), or erases, by tool; a double tap removes a mark
/// with any tool. Two fingers pinch the selected mark (scale, turn, move) or, with none selected,
/// zoom the video ([onZoomStart], [onZoomUpdate], in global coordinates).
/// Sized to the video itself (inside its AspectRatio).
class TelestratorCanvas extends StatefulWidget {
  const TelestratorCanvas({
    super.key,
    required this.controller,
    required this.enabled,
    this.onZoomStart,
    this.onZoomUpdate,
  });

  final TelestratorController controller;
  final bool enabled;
  final ValueChanged<Offset>? onZoomStart;
  final void Function(Offset focal, double scale)? onZoomUpdate;

  @override
  State<TelestratorCanvas> createState() => _TelestratorCanvasState();
}

enum _Gesture { draw, move, handle, erase, pinch, zoom, none }

class _TelestratorCanvasState extends State<TelestratorCanvas> {
  _Gesture? _gesture;

  /// Two fingers were down since the first one touched: the finger left after a pinch does nothing.
  bool _multi = false;
  int _fingers = 0;
  int _handle = 0;
  Offset _last = Offset.zero;
  double _lastScale = 1;
  double _lastRotation = 0;
  Offset? _doubleTapAt;

  /// Where the finger went down: a drag only starts past the slop, and should act from here.
  Offset? _down;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final c = widget.controller;
      final size = box.biggest;
      final paint = CustomPaint(painter: _StrokePainter(c), size: size);
      if (!widget.enabled) return paint;
      Offset rel(Offset p) => Offset(p.dx / size.width, p.dy / size.height);
      Offset inside(Offset p) => Offset((p.dx / size.width).clamp(0, 1), (p.dy / size.height).clamp(0, 1));
      return Listener(
        onPointerDown: (e) {
          if (_fingers++ == 0) {
            _multi = false;
            _down = e.localPosition;
          }
        },
        onPointerUp: (_) => _fingers--,
        onPointerCancel: (_) => _fingers--,
        child: GestureDetector(
          key: const ValueKey('review-canvas'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            final p = d.localFocalPoint;
            _last = p;
            _lastScale = 1;
            _lastRotation = 0;
            if (d.pointerCount > 1) {
              _multi = true;
              if (c.selected != null) {
                _gesture = _Gesture.pinch;
                c.transformSelected(rel(p), rel(p), 1, 0, size, first: true);
              } else if (widget.onZoomStart case final start?) {
                _gesture = _Gesture.zoom;
                start(d.focalPoint);
              } else {
                _gesture = _Gesture.none;
              }
              return;
            }
            if (_multi) {
              _gesture = _Gesture.none;
              return;
            }
            final down = _down ?? p;
            switch (c.tool) {
              case TelestratorTool.select:
                if (c.handleAt(rel(down), size) case final h?) {
                  _gesture = _Gesture.handle;
                  _handle = h;
                  c.dragHandle(h, rel(p), size, first: true);
                } else if (c.select(rel(down), size)) {
                  // A drag picks up the mark under the finger and carries it.
                  _gesture = _Gesture.move;
                  c.moveSelected(rel(p - down), first: true);
                } else {
                  _gesture = _Gesture.none;
                }
              case TelestratorTool.eraser:
                _gesture = _Gesture.erase;
                c
                  ..eraseAt(inside(down), size, first: true)
                  ..eraseAt(inside(p), size);
              case _:
                _gesture = _Gesture.draw;
                c
                  ..begin(inside(down))
                  ..extend(inside(p));
            }
          },
          onScaleUpdate: (d) {
            final p = d.localFocalPoint;
            switch (_gesture) {
              case _Gesture.draw:
                c.extend(inside(p));
              case _Gesture.move:
                c.moveSelected(rel(p - _last));
              case _Gesture.handle:
                c.dragHandle(_handle, rel(p), size);
              case _Gesture.erase:
                c.eraseAt(inside(p), size);
              case _Gesture.pinch:
                c.transformSelected(rel(_last), rel(p), d.scale / _lastScale, d.rotation - _lastRotation, size);
              case _Gesture.zoom:
                widget.onZoomUpdate?.call(d.focalPoint, d.scale);
              case _Gesture.none || null:
                break;
            }
            _last = p;
            _lastScale = d.scale;
            _lastRotation = d.rotation;
          },
          onScaleEnd: (d) {
            // Fingers still down: a second one arrived (the mark being drawn was not meant) or one of
            // two lifted.
            if (_gesture == _Gesture.draw) d.pointerCount > 0 ? c.cancel() : c.end();
            _gesture = null;
          },
          onTapUp: (d) {
            if (c.tool == TelestratorTool.select) c.select(inside(d.localPosition), size);
            if (c.tool == TelestratorTool.eraser) c.eraseAt(inside(d.localPosition), size, first: true);
          },
          onDoubleTapDown: (d) => _doubleTapAt = inside(d.localPosition),
          onDoubleTap: () {
            if (_doubleTapAt case final p?) c.eraseAt(p, size, first: true);
          },
          child: paint,
        ),
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
        _mark(canvas, s, pts, width + 10, halo.withValues(alpha: 0.6));
      }
      _mark(canvas, s, pts, width, s.color);
    }
    // Handles to drag: white dots with a dark rim, readable on any picture.
    for (final h in controller.handles(size)) {
      canvas
        ..drawCircle(h, 10, Paint()..color = Colors.white)
        ..drawCircle(
          h,
          10,
          Paint()
            ..color = Colors.black87
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
  }

  static void _mark(Canvas canvas, TelestratorStroke s, List<Offset> pts, double width, Color color) {
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
    switch (s.tool) {
      case TelestratorTool.line:
        canvas.drawLine(pts.first, pts.last, paint);
      case TelestratorTool.arrow:
        canvas.drawLine(pts.first, pts.last, paint);
        _arrowHead(canvas, pts.first, pts.last, width, paint);
      case TelestratorTool.circle:
        final box = Rect.fromPoints(pts.first, pts.last);
        canvas
          ..save()
          ..translate(box.center.dx, box.center.dy)
          ..rotate(s.angle)
          ..drawOval(Rect.fromCenter(center: Offset.zero, width: box.width, height: box.height), paint)
          ..restore();
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

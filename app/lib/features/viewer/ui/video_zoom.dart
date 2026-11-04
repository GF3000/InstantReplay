import 'package:flutter/widgets.dart';

/// Pinch zoom on the review video (and the drawing on it): 1× to [max] about the fingers, panned
/// with them, and never leaving an empty edge inside the video's box.
class VideoZoomController extends ChangeNotifier {
  static const max = 5.0;

  double _scale = 1;
  Offset _offset = Offset.zero;
  double _startScale = 1;

  /// The point of the picture under the fingers when the pinch started (unzoomed box coordinates).
  Offset _anchor = Offset.zero;

  double get scale => _scale;
  bool get zoomed => _scale > 1.01;

  /// Box coordinates to screen: scaled by [scale], then shifted.
  Matrix4 get matrix => Matrix4.diagonal3Values(_scale, _scale, 1)..setTranslationRaw(_offset.dx, _offset.dy, 0);

  /// A pinch starts with the fingers at [focal] (box coordinates).
  void begin(Offset focal) {
    _startScale = _scale;
    _anchor = (focal - _offset) / _scale;
  }

  /// The fingers are at [focal], [scale] times as far apart as at [begin].
  void update(Offset focal, double scale, Size box) {
    _scale = (_startScale * scale).clamp(1.0, max);
    final o = focal - _anchor * _scale;
    _offset = Offset(o.dx.clamp(box.width * (1 - _scale), 0), o.dy.clamp(box.height * (1 - _scale), 0));
    notifyListeners();
  }

  void reset() {
    if (_scale == 1 && _offset == Offset.zero) return;
    _scale = 1;
    _offset = Offset.zero;
    notifyListeners();
  }
}

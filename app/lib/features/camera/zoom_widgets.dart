import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ui/ir_colors.dart';
import '../../l10n/app_localizations.dart';

/// `−  1.5×  +` over a video: steps the Camera's zoom (SPEC §3.1). Tap the value for 1×. Used on
/// the Camera's own preview and on a viewer's live view; both change the same zoom.
class ZoomControl extends StatelessWidget {
  const ZoomControl({
    super.key,
    required this.ratio,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.keyPrefix = 'zoom',
  });

  static const step = 0.25;

  final double ratio;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(IconData icon, String tip, double? to, String key) => IconButton(
          key: ValueKey('$keyPrefix-$key'),
          color: Colors.white,
          disabledColor: Colors.white38,
          tooltip: tip,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: enabled && to != null ? () => onChanged(to) : null,
          icon: Icon(icon),
        );
    final down = ratio > 1 ? (ratio - step).clamp(1.0, max) : null;
    final up = ratio < max ? (ratio + step).clamp(1.0, max) : null;
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        button(Icons.zoom_out, l10n.zoomOut, down, 'out'),
        InkWell(
          key: ValueKey('$keyPrefix-reset'),
          onTap: enabled && ratio > 1 ? () => onChanged(1) : null,
          child: SizedBox(
            width: 52,
            height: 48,
            child: Center(
              child: Text(
                formatZoom(ratio),
                semanticsLabel: l10n.zoomReset,
                style: irMono(15, color: Colors.white),
              ),
            ),
          ),
        ),
        button(Icons.zoom_in, l10n.zoomIn, up, 'in'),
      ]),
    );
  }
}

/// `1×`, `1.5×`, `2.25×`.
String formatZoom(double r) {
  final text = r.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text×';
}

/// Two-finger pinch over [child] zooms the Camera; one finger passes through to [child].
/// Changes are sent at most every [interval], the last one always.
class ZoomPinch extends StatefulWidget {
  const ZoomPinch({
    super.key,
    required this.ratio,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.child,
    this.interval = const Duration(milliseconds: 80),
  });

  final double ratio;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final Widget child;
  final Duration interval;

  @override
  State<ZoomPinch> createState() => _ZoomPinchState();
}

class _ZoomPinchState extends State<ZoomPinch> {
  double? _base;
  double? _pending;
  Timer? _throttle;

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  void _send(double r) {
    _pending = r;
    if (_throttle?.isActive ?? false) return;
    _flush();
    _throttle = Timer(widget.interval, _flush);
  }

  void _flush() {
    final r = _pending;
    _pending = null;
    if (r != null) widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: widget.enabled ? (d) => _base = d.pointerCount >= 2 ? widget.ratio : null : null,
        onScaleUpdate: widget.enabled
            ? (d) {
                if (d.pointerCount < 2) return;
                final base = _base ??= widget.ratio;
                _send((base * d.scale).clamp(1.0, widget.max));
              }
            : null,
        onScaleEnd: widget.enabled
            ? (_) {
                _base = null;
                _flush();
              }
            : null,
        child: widget.child,
      );
}

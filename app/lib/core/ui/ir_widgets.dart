import 'package:flutter/material.dart';

import 'ir_colors.dart';

/// Looping decorative animations (blinking dots, mic level). Tests turn them off in
/// test/flutter_test_config.dart so `pumpAndSettle` can settle. Any new looping animation must
/// check [loops] (and `MediaQuery.disableAnimations`).
abstract final class IrMotion {
  static bool loops = true;

  static bool of(BuildContext context) => loops && !MediaQuery.of(context).disableAnimations;
}

/// A "hardware key": the signature control of the control-room style. A raised graphite button
/// with an optional glowing LED strip on top ([led]). Use it for primary actions such as
/// "Guardar jugada" or "Escanear el QR"; the rest of the UI stays flat.
class IrKey extends StatelessWidget {
  const IrKey({
    super.key,
    required this.onPressed,
    required this.child,
    this.led,
    this.borderColor,
    this.minHeight = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final Widget child;

  /// Colour of the LED strip across the top; null draws none.
  final Color? led;

  /// Border override (e.g. a team colour or [IrColors.signal] when selected).
  final Color? borderColor;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(6);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor ?? c.lineStrong),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.keyTop, c.keyBottom]),
            boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(0, 2))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Stack(children: [
                  if (led != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      top: 7,
                      height: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: led,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [BoxShadow(color: led!.withValues(alpha: 0.8), blurRadius: 10)],
                        ),
                      ),
                    ),
                  Padding(
                    padding: padding.add(EdgeInsets.only(top: led != null ? 8 : 0)),
                    child: Align(widthFactor: 1, heightFactor: 1, child: child),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A flat bordered panel (the base surface of the style). No shadows, radius 4.
class IrPanel extends StatelessWidget {
  const IrPanel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.borderColor, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor ?? c.line),
      ),
      child: child,
    );
  }
}

/// A segmented control in the style: one bordered strip, the selected segment filled with
/// [IrColors.signal]. Every segment is at least 48 dp tall.
class IrSegmented<T> extends StatelessWidget {
  const IrSegmented({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.height = 48,
    this.mono = false,
  });

  final List<T> values;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T>? onChanged;
  final double height;

  /// Use the monospaced face (for speeds, seconds…).
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Container(
      height: height,
      decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) VerticalDivider(width: 1, thickness: 1, color: c.line),
          Expanded(
            child: _Segment(
              label: labelOf(values[i]),
              selected: values[i] == selected,
              mono: mono,
              onTap: onChanged == null ? null : () => onChanged!(values[i]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.mono, required this.onTap});

  final String label;
  final bool selected;
  final bool mono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final fg = selected ? c.onSignal : c.text;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.signal : c.surface,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono ? irMono(15, weight: FontWeight.w600, color: fg) : TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter chip: a small colour square, a label and an optional count.
class IrFilterChip extends StatelessWidget {
  const IrFilterChip({super.key, required this.label, required this.selected, required this.onTap, this.color, this.count});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.signalSoft : c.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: selected ? c.signal : c.line)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (color != null) ...[
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
                  const SizedBox(width: 7),
                ],
                Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count', style: irMono(12, weight: FontWeight.w500, color: c.muted)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small blinking dot (on air, recording).
class IrLiveDot extends StatefulWidget {
  const IrLiveDot({super.key, required this.color, this.size = 10, this.blink = true});

  final Color color;
  final double size;
  final bool blink;

  @override
  State<IrLiveDot> createState() => _IrLiveDotState();
}

class _IrLiveDotState extends State<IrLiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(IrLiveDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.blink && IrMotion.of(context);
    if (run && !_c.isAnimating) _c.repeat(reverse: true);
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 8)],
      ),
    );
    if (!widget.blink || !IrMotion.of(context)) return dot;
    return FadeTransition(opacity: Tween(begin: 1.0, end: 0.3).animate(_c), child: dot);
  }
}

/// The one-tap microphone toggle used in every live screen (viewer and camera). Visual only:
/// the caller owns the state. Red means "YouTube hears nothing".
class IrMicToggle extends StatelessWidget {
  const IrMicToggle({
    super.key,
    required this.open,
    required this.onTap,
    this.openLabel,
    this.closedLabel,
    this.subtitle,
    this.height = 44,
  });

  final bool open;
  final VoidCallback? onTap;

  /// Labels shown next to the icon; null makes it icon-only (compact top bars).
  final String? openLabel;
  final String? closedLabel;
  final String? subtitle;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final fg = open ? c.text : c.onLive;
    final label = open ? openLabel : closedLabel;
    return Semantics(
      toggled: open,
      button: true,
      label: label,
      child: Material(
        color: open ? c.surface : c.live,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: open ? c.line : c.live)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height, minWidth: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(open ? Icons.mic : Icons.mic_off, size: 20, color: fg),
                if (open) ...[const SizedBox(width: 4), _Level(color: c.ok)],
                if (label != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
                      if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: open ? c.muted : fg)),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decorative "level meter" bars. They suggest the mic is live; they do not measure audio.
class _Level extends StatefulWidget {
  const _Level({required this.color});

  final Color color;

  @override
  State<_Level> createState() => _LevelState();
}

class _LevelState extends State<_Level> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = IrMotion.of(context);
    if (run && !_c.isAnimating) _c.repeat(reverse: true);
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !IrMotion.of(context);
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final phase in const [0.0, 0.4, 0.75])
              Container(
                margin: const EdgeInsets.only(left: 2),
                width: 3,
                height: still ? 10 : 4 + 12 * ((_c.value + phase) % 1.0),
                color: widget.color,
              ),
          ],
        ),
      ),
    );
  }
}

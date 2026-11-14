import 'package:flutter/material.dart';

import 'ir_colors.dart';

/// Looping decorative animations (blinking dots). Tests turn them off in
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
                child: Stack(alignment: Alignment.center, children: [
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
            constraints: const BoxConstraints(minHeight: 48),
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
///
/// [level] (0…1, see [IrMicToggle.levelFromDbfs]) is what the microphone really hears; it draws
/// a small meter next to the icon, dimmed while muted so the user sees they are talking into a
/// closed mic. Null (no stream, no permission, a Camera that does not send it) draws no meter.
class IrMicToggle extends StatelessWidget {
  const IrMicToggle({
    super.key,
    required this.open,
    required this.onTap,
    this.level,
    this.openLabel,
    this.closedLabel,
    this.subtitle,
    this.height = 48,
  });

  final bool open;
  final VoidCallback? onTap;

  /// Microphone level 0…1; null shows no meter.
  final double? level;

  /// Labels shown next to the icon; null makes it icon-only (compact top bars).
  final String? openLabel;
  final String? closedLabel;
  final String? subtitle;
  final double height;

  /// Bars of the meter.
  static const bars = 4;

  /// dBFS → meter level: −60 dB (or quieter) → 0, −6 dB (or louder) → 1, linear in dB. Null stays
  /// null (no microphone).
  static double? levelFromDbfs(double? db) {
    if (db == null || db.isNaN) return null;
    return ((db - _floorDb) / (_topDb - _floorDb)).clamp(0.0, 1.0);
  }

  static const _floorDb = -60.0;
  static const _topDb = -6.0;

  /// How many of [count] bars a [level] lights: bar i (from 0) once the level passes i/count,
  /// so any sound above the floor lights the first one and only near clipping the last.
  static int litBars(double level, [int count = bars]) {
    var lit = 0;
    for (var i = 0; i < count; i++) {
      if (level > i / count) lit = i + 1;
    }
    return lit;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final fg = open ? c.text : c.onLive;
    final label = open ? openLabel : closedLabel;
    final l = level;
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
                if (l != null) ...[const SizedBox(width: 4), _LevelMeter(level: l, open: open)],
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

/// The mic meter: [IrMicToggle.bars] rising bars, lit from the left with the real level (green,
/// the last one amber near clipping). Muted: drawn in the toggle's text colour, dimmed. No
/// animation; the bars just follow the values as they arrive.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.open});

  final double level;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final lit = IrMicToggle.litBars(level);
    const n = IrMicToggle.bars;
    return SizedBox(
      key: const ValueKey('ir-mic-level'),
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < n; i++)
            Container(
              key: ValueKey('ir-mic-bar-$i-${i < lit ? 'on' : 'off'}'),
              margin: const EdgeInsets.only(left: 2),
              width: 3,
              height: 4.0 + 12 * (i + 1) / n,
              color: switch ((open, i < lit)) {
                (true, true) => i == n - 1 ? c.warn : c.ok,
                (true, false) => c.line,
                (false, true) => c.onLive.withValues(alpha: 0.6),
                (false, false) => c.onLive.withValues(alpha: 0.2),
              },
            ),
        ],
      ),
    );
  }
}

/// A short note with an icon in a bordered strip (e.g. "same Wi-Fi" next to pairing).
class IrNote extends StatelessWidget {
  const IrNote({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;

  /// Icon colour; [IrColors.info] by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color ?? c.info),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.3, color: c.text))),
      ]),
    );
  }
}

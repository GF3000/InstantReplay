import 'package:flutter/material.dart';

/// Font families bundled in app/fonts (OFL). The web Viewer is served offline by the Camera,
/// so fonts must never be fetched from the internet.
abstract final class IrFonts {
  /// UI text: IBM Plex Sans Condensed.
  static const sans = 'PlexCondensed';

  /// Numbers, clocks, timecodes and codes: IBM Plex Mono.
  static const mono = 'PlexMono';
}

/// The "control room" palette (redesign B). Read it with `context.ir`.
///
/// Semantic colours are kept apart from the accent: [signal] (amber) marks the main action and
/// the current selection, [live] means "YouTube sees/hears this", [ok]/[warn] are states.
@immutable
class IrColors extends ThemeExtension<IrColors> {
  const IrColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.muted,
    required this.signal,
    required this.onSignal,
    required this.signalSoft,
    required this.live,
    required this.onLive,
    required this.liveSoft,
    required this.liveText,
    required this.ok,
    required this.warn,
    required this.warnText,
    required this.info,
    required this.keyTop,
    required this.keyBottom,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color line;
  final Color lineStrong;
  final Color text;
  final Color muted;

  /// Accent: primary action, selection, LED strip on keys.
  final Color signal;
  final Color onSignal;

  /// Background of a selected chip/segment/tab.
  final Color signalSoft;

  /// On air / recording / destructive.
  final Color live;
  final Color onLive;
  final Color liveSoft;

  /// [live] used as text on dark surfaces (slightly lighter for contrast).
  final Color liveText;
  final Color ok;
  final Color warn;
  final Color warnText;
  final Color info;

  /// Gradient of a "hardware key" (see IrKey).
  final Color keyTop;
  final Color keyBottom;

  static const dark = IrColors(
    bg: Color(0xFF0F1012),
    surface: Color(0xFF17191C),
    surfaceHigh: Color(0xFF1E2125),
    line: Color(0xFF2C3036),
    lineStrong: Color(0xFF3A3E45),
    text: Color(0xFFECEDEF),
    muted: Color(0xFF9AA0A8),
    signal: Color(0xFFFFC107),
    onSignal: Color(0xFF15120A),
    signalSoft: Color(0xFF2A2410),
    live: Color(0xFFFF453A),
    onLive: Color(0xFFFFFFFF),
    liveSoft: Color(0xFF1E1112),
    liveText: Color(0xFFFF6A61),
    ok: Color(0xFF32D74B),
    warn: Color(0xFFFFC107),
    warnText: Color(0xFFF2D27A),
    info: Color(0xFF4D9BFF),
    keyTop: Color(0xFF25282D),
    keyBottom: Color(0xFF1A1C20),
  );

  static const light = IrColors(
    bg: Color(0xFFF4F5F6),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE9EBEE),
    line: Color(0xFFD5D8DD),
    lineStrong: Color(0xFFB9BDC4),
    text: Color(0xFF0F1012),
    muted: Color(0xFF474C54),
    signal: Color(0xFF5C4300),
    onSignal: Color(0xFFFFFFFF),
    signalSoft: Color(0xFFFFF1C7),
    live: Color(0xFFC62828),
    onLive: Color(0xFFFFFFFF),
    liveSoft: Color(0xFFFDECEA),
    liveText: Color(0xFFB71C1C),
    ok: Color(0xFF1B7F33),
    warn: Color(0xFF8A6400),
    warnText: Color(0xFF6B4E00),
    info: Color(0xFF1565C0),
    keyTop: Color(0xFFFFFFFF),
    keyBottom: Color(0xFFEDEFF2),
  );

  @override
  IrColors copyWith() => this;

  @override
  IrColors lerp(ThemeExtension<IrColors>? other, double t) => t < 0.5 || other is! IrColors ? this : other;
}

extension IrContext on BuildContext {
  IrColors get ir => Theme.of(this).extension<IrColors>() ?? IrColors.dark;
}

/// Text style for numbers (scores, clocks, durations, codes): monospaced, tabular.
TextStyle irMono(double size, {FontWeight weight = FontWeight.w700, Color? color, double? height}) => TextStyle(
      fontFamily: IrFonts.mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

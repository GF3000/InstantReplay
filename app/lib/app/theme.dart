import 'package:flutter/material.dart';

import '../core/ui/ir_colors.dart';

/// "Control room" theme (redesign B): graphite surfaces, hairline borders, amber signal,
/// IBM Plex Sans Condensed for text and IBM Plex Mono for numbers. Dark high-contrast by default
/// (D20, N10 ≥ 7:1); light is available. Primary buttons are at least 56 dp tall.
/// Feature code reads the palette with `context.ir` (lib/core/ui/ir_colors.dart).
abstract final class AppTheme {
  static final dark = _build(IrColors.dark, Brightness.dark);
  static final light = _build(IrColors.light, Brightness.light);

  static ThemeData _build(IrColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.signal,
      onPrimary: c.onSignal,
      primaryContainer: c.signalSoft,
      onPrimaryContainer: c.text,
      secondary: c.signal,
      onSecondary: c.onSignal,
      secondaryContainer: c.surfaceHigh,
      onSecondaryContainer: c.text,
      tertiary: c.info,
      onTertiary: c.bg,
      tertiaryContainer: c.surfaceHigh,
      onTertiaryContainer: c.text,
      error: c.live,
      onError: c.onLive,
      errorContainer: c.liveSoft,
      onErrorContainer: c.liveText,
      surface: c.bg,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceHigh,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.lineStrong,
      outlineVariant: c.line,
      inverseSurface: c.text,
      onInverseSurface: c.bg,
      inversePrimary: c.signal,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    const primarySize = Size(64, 56);
    final r4 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
    final r6 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    final base = ThemeData(brightness: brightness, fontFamily: IrFonts.sans);
    final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text).copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        );
    return ThemeData(
      brightness: brightness,
      fontFamily: IrFonts.sans, // bundled (app/fonts): the web build must not fetch fonts.gstatic.com
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.line,
      extensions: [c],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: c.line)),
        titleTextStyle: TextStyle(fontFamily: IrFonts.sans, fontSize: 20, fontWeight: FontWeight.w700, color: c.text),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.line)),
      ),
      listTileTheme: ListTileThemeData(iconColor: c.muted, textColor: c.text),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.lineStrong)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          side: BorderSide(color: c.lineStrong),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: c.lineStrong)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceHigh,
        contentTextStyle: TextStyle(fontFamily: IrFonts.sans, fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
        actionTextColor: c.signal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.lineStrong)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.lineStrong)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.lineStrong)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.signal, width: 2)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.bg,
        selectedColor: c.signalSoft,
        side: BorderSide(color: c.line),
        shape: r4,
        labelStyle: TextStyle(fontFamily: IrFonts.sans, fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(r4),
          side: WidgetStatePropertyAll(BorderSide(color: c.line)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.signal : c.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onSignal : c.text),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ok : c.lineStrong),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: c.signal, thumbColor: c.signal, inactiveTrackColor: c.line),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.signal, linearTrackColor: c.line),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: primarySize, shape: r6)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(minimumSize: primarySize, shape: r6)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: primarySize, shape: r6, side: BorderSide(color: c.lineStrong), foregroundColor: c.text),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: r4)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: r4)),
    );
  }
}

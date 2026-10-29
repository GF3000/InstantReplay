import 'package:flutter/material.dart';

/// Dark high-contrast by default (D20); light is available. Primary buttons are at least 56 dp tall.
abstract final class AppTheme {
  static final dark = _build(Brightness.dark);
  static final light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: Colors.amber, brightness: brightness, contrastLevel: 1);
    const primarySize = Size(64, 56);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? Colors.black : scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: primarySize)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(minimumSize: primarySize)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: primarySize)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
    );
  }
}

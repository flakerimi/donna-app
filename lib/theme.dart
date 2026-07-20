import 'package:flutter/material.dart';

/// Claude-app palette: warm ivory light mode, charcoal dark mode, terracotta
/// accent, serif display for greetings and titles.
abstract final class DonnaTheme {
  static const terracotta = Color(0xFFD97757);
  static const inkLight = Color(0xFF1F1E1D);
  static const ivory = Color(0xFFFAF9F5);
  static const ivoryContainer = Color(0xFFF0EEE5);
  static const ivoryBubble = Color(0xFFE8E4D8);
  static const charcoal = Color(0xFF262624);
  static const charcoalContainer = Color(0xFF30302E);
  static const charcoalBubble = Color(0xFF3A3937);
  static const parchmentText = Color(0xFFECECEA);

  static const serif = 'Georgia';

  static ThemeData light() => _base(
    const ColorScheme.light(
      primary: terracotta,
      onPrimary: Colors.white,
      primaryContainer: ivoryBubble,
      onPrimaryContainer: inkLight,
      surface: ivory,
      onSurface: inkLight,
      surfaceContainerHighest: ivoryContainer,
      surfaceContainerHigh: ivoryContainer,
      surfaceContainerLow: ivory,
      outline: Color(0xFF8A8779),
    ),
  );

  static ThemeData dark() => _base(
    const ColorScheme.dark(
      primary: terracotta,
      onPrimary: Colors.white,
      primaryContainer: charcoalBubble,
      onPrimaryContainer: parchmentText,
      surface: charcoal,
      onSurface: parchmentText,
      surfaceContainerHighest: charcoalContainer,
      surfaceContainerHigh: charcoalContainer,
      surfaceContainerLow: charcoal,
      outline: Color(0xFF8F8D86),
    ),
  );

  static ThemeData _base(ColorScheme scheme) => ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: serif,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
    dividerTheme: DividerThemeData(
      color: scheme.outline.withValues(alpha: 0.2),
      thickness: 0.5,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.onSurface,
      contentTextStyle: TextStyle(color: scheme.surface),
    ),
  );

  /// The spark — Donna's stand-in for Claude's asterisk.
  static Widget spark(BuildContext context, {double size = 16}) => Text(
    '✳',
    style: TextStyle(
      fontSize: size,
      height: 1,
      color: Theme.of(context).colorScheme.primary,
    ),
  );

  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late, Flak';
    if (h < 12) return 'Good morning, Flak';
    if (h < 18) return 'Good afternoon, Flak';
    return 'Good evening, Flak';
  }
}

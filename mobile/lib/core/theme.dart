import 'package:flutter/material.dart';

class ChamaColors {
  static const purple = Color(0xFF5B2BB5);
  static const deep = Color(0xFF2E0A5E);
  static const soft = Color(0xFFF1E9FF);
  static const green = Color(0xFF16A34A);
  static const greenSoft = Color(0xFFE8F8EC);
  static const canvas = Color(0xFFF7F4FC);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1D1233);
  static const muted = Color(0xFF766A86);
  static const line = Color(0xFFEAE2F4);
  static const danger = Color(0xFFD92D20);
  static const warning = Color(0xFFC47A00);
  static const warningSoft = Color(0xFFFFF4DF);
}

final TextStyle moneyStyle = const TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w800,
  letterSpacing: -0.7,
);

ThemeData buildChamaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: ChamaColors.purple,
          brightness: Brightness.light,
        ).copyWith(
          primary: ChamaColors.purple,
          secondary: ChamaColors.green,
          surface: ChamaColors.surface,
          onSurface: ChamaColors.ink,
          error: ChamaColors.danger,
        ),
    scaffoldBackgroundColor: ChamaColors.canvas,
  );

  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(
      color: ChamaColors.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.05,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      color: ChamaColors.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.1,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      color: ChamaColors.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.15,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      color: ChamaColors.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.35,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      color: ChamaColors.ink,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: base.textTheme.titleSmall?.copyWith(
      color: ChamaColors.ink,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      color: ChamaColors.ink,
      height: 1.45,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      color: ChamaColors.ink,
      height: 1.45,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      color: ChamaColors.muted,
      height: 1.4,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: ChamaColors.canvas,
      foregroundColor: ChamaColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ChamaColors.ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: ChamaColors.line,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ChamaColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      hintStyle: const TextStyle(color: ChamaColors.muted, fontSize: 15),
      labelStyle: const TextStyle(color: ChamaColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ChamaColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ChamaColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ChamaColors.purple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ChamaColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ChamaColors.danger, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ChamaColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ChamaColors.purple,
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: const BorderSide(color: ChamaColors.line),
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ChamaColors.purple,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ChamaColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ChamaColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ChamaColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: ChamaColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: ChamaColors.soft,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? ChamaColors.purple
              : ChamaColors.muted,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? ChamaColors.purple
              : ChamaColors.muted,
          size: 23,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ChamaColors.purple,
      linearTrackColor: ChamaColors.soft,
    ),
  );
}

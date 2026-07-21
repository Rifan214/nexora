import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTheme {
  static const _primary = Color(0xFF005BBF);
  static const _primaryContainer = Color(0xFF1A73E8);
  static const _secondary = Color(0xFF006876);
  static const _secondaryContainer = Color(0xFF58E6FF);
  static const _lightSurface = Color(0xFFF9F9FF);
  static const _lightSurfaceLow = Color(0xFFF2F3FD);
  static const _lightSurfaceContainer = Color(0xFFECECF7);
  static const _lightSurfaceHigh = Color(0xFFE6E8F2);
  static const _lightSurfaceHighest = Color(0xFFE0E2EC);
  static const _lightOnSurface = Color(0xFF191C23);
  static const _lightOnSurfaceVariant = Color(0xFF414754);
  static const _lightOutline = Color(0xFF727785);
  static const _lightOutlineVariant = Color(0xFFC1C6D6);
  static const _lightInputFill = Color(0xFFF1F3F4);

  static final ColorScheme _lightColorScheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: _primary,
    onPrimary: Colors.white,
    primaryContainer: _primaryContainer,
    onPrimaryContainer: Colors.white,
    secondary: _secondary,
    onSecondary: Colors.white,
    secondaryContainer: _secondaryContainer,
    onSecondaryContainer: const Color(0xFF006573),
    tertiary: const Color(0xFF006D2B),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFF24883F),
    onTertiaryContainer: const Color(0xFF000601),
    error: const Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF93000A),
    surface: _lightSurface,
    onSurface: _lightOnSurface,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: _lightSurfaceLow,
    surfaceContainer: _lightSurfaceContainer,
    surfaceContainerHigh: _lightSurfaceHigh,
    surfaceContainerHighest: _lightSurfaceHighest,
    onSurfaceVariant: _lightOnSurfaceVariant,
    outline: _lightOutline,
    outlineVariant: _lightOutlineVariant,
    shadow: Colors.black,
  );

  static final ColorScheme _darkColorScheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFFADC7FF),
    onPrimary: const Color(0xFF002F65),
    primaryContainer: const Color(0xFF004493),
    onPrimaryContainer: const Color(0xFFD8E2FF),
    secondary: const Color(0xFF44D8F1),
    onSecondary: const Color(0xFF00363E),
    secondaryContainer: const Color(0xFF006573),
    onSecondaryContainer: const Color(0xFFA1EFFF),
    tertiary: const Color(0xFF7ADB87),
    onTertiary: const Color(0xFF003915),
    tertiaryContainer: const Color(0xFF00531F),
    onTertiaryContainer: const Color(0xFF96F8A1),
    surface: const Color(0xFF111318),
    onSurface: const Color(0xFFE2E2EA),
    surfaceContainerLowest: const Color(0xFF0C0E13),
    surfaceContainerLow: const Color(0xFF191C23),
    surfaceContainer: const Color(0xFF1D2027),
    surfaceContainerHigh: const Color(0xFF272A32),
    surfaceContainerHighest: const Color(0xFF32353D),
    onSurfaceVariant: const Color(0xFFC1C6D6),
    outline: const Color(0xFF8B909E),
    outlineVariant: const Color(0xFF414754),
    shadow: Colors.black,
  );

  static ThemeData get light => _buildTheme(_lightColorScheme);

  static ThemeData get dark => _buildTheme(_darkColorScheme);

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final textTheme = _textTheme(colorScheme);
    final inputFillColor = colorScheme.brightness == Brightness.light
        ? _lightInputFill
        : colorScheme.surfaceContainerHigh;
    final inputBorder = OutlineInputBorder(
      borderRadius: AppRadii.input,
      borderSide: BorderSide.none,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: 'Inter',
      typography: Typography.material2021(),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium?.copyWith(
          color: colorScheme.primary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const StadiumBorder(),
          textStyle: textTheme.titleMedium?.copyWith(
            color: colorScheme.onPrimary,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const StadiumBorder(),
          backgroundColor: colorScheme.surfaceContainerHigh,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          textStyle: textTheme.titleMedium,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        shadowColor: colorScheme.shadow.withAlpha(12),
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.card),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: inputFillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: colorScheme.outlineVariant,
        ),
        prefixIconColor: colorScheme.outline,
        suffixIconColor: colorScheme.primary,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.input,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.input,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.input,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: AppSizes.navigationHeight,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: isSelected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
            size: 26,
          );
        }),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    return const TextTheme(
      displayLarge: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1.17,
        letterSpacing: 0,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.29,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.33,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: 0,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.33,
        letterSpacing: 0,
      ),
    ).apply(
      fontFamily: 'Inter',
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
  }
}

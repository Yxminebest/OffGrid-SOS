import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'style_tokens.dart';

export 'app_palette.dart';
export 'style_tokens.dart';

extension AppThemeContext on BuildContext {
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light);
}

ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final p = dark ? AppPalette.dark : AppPalette.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.info,
        brightness: brightness,
      ).copyWith(
        primary: p.info,
        onPrimary: dark ? AppColors.onPrimaryDark : Colors.white,
        secondary: p.rescue,
        surface: p.surface,
        onSurface: p.text,
        onSurfaceVariant: p.muted,
        outline: p.border,
        outlineVariant: p.border,
        error: dark ? AppColors.errorDark : AppColors.error,
        errorContainer: dark
            ? AppColors.errorSurfaceDark
            : AppColors.errorSurfaceLight,
        onErrorContainer: dark ? AppColors.onErrorDark : AppColors.onErrorLight,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
  );
  final text = base.textTheme
      .apply(bodyColor: p.text, displayColor: p.text)
      .copyWith(
        headlineLarge: TextStyle(
          fontSize: 30,
          height: 1.25,
          fontWeight: FontWeight.w800,
          color: p.text,
        ),
        headlineMedium: TextStyle(
          fontSize: 25,
          height: 1.35,
          fontWeight: FontWeight.w800,
          color: p.text,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: p.text),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: p.text),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
        labelLarge: TextStyle(
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
      )
      .apply(fontFamily: AppMetrics.fontFamily);
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    textTheme: text,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape.copyWith(side: BorderSide(color: p.border)),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 24),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.muted),
      labelStyle: TextStyle(color: p.muted),
      prefixIconColor: p.muted,
      suffixIconColor: p.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        borderSide: BorderSide(color: p.info, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.brandInk,
        minimumSize: const Size(
          AppMetrics.minimumTapSize,
          AppMetrics.buttonHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(
          AppMetrics.minimumTapSize,
          AppMetrics.buttonHeight,
        ),
        foregroundColor: p.text,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size.square(AppMetrics.minimumTapSize),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppMetrics.minimumTapSize),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      elevation: 0,
      indicatorColor: p.info.withValues(alpha: .13),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? p.info : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? p.info : p.muted,
          size: 24,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      selectedColor: p.info.withValues(alpha: .14),
      side: BorderSide(color: p.border),
      labelStyle: TextStyle(color: p.text),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.chipRadius),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.info,
      textColor: p.text,
      minVerticalPadding: 12,
      subtitleTextStyle: text.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: shape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.dialogRadius),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppMetrics.sheetRadius),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? AppColors.snackbarDark : AppColors.snackbarLight,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        height: 1.5,
      ),
      actionTextColor: AppColors.snackbarAction,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.controlRadius),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

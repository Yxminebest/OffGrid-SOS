import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const sos = Color(0xFFC93643);
  static const error = Color(0xFFC93643);
  static const rescue = Color(0xFF316FB8);
  static const info = Color(0xFF805B00);
  static const success = Color(0xFF785B13);
  static const pending = Color(0xFF99601B);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.border,
    required this.text,
    required this.muted,
    required this.info,
    required this.rescue,
    required this.success,
    required this.pending,
  });
  final Color background, surface, surfaceSoft, border, text, muted;
  final Color info, rescue, success, pending;

  static const light = AppPalette(
    background: Color(0xFFFFFBF0),
    surface: Colors.white,
    surfaceSoft: Color(0xFFFFF1C2),
    border: Color(0xFFE5DDC5),
    text: Color(0xFF302A1D),
    muted: Color(0xFF71654F),
    info: Color(0xFF805B00),
    rescue: Color(0xFF316FB8),
    success: Color(0xFF785B13),
    pending: Color(0xFF99601B),
  );
  static const dark = AppPalette(
    background: Color(0xFF191710),
    surface: Color(0xFF242016),
    surfaceSoft: Color(0xFF322B19),
    border: Color(0xFF51462B),
    text: Color(0xFFFFF6DE),
    muted: Color(0xFFC3B796),
    info: Color(0xFFF3CA55),
    rescue: Color(0xFF92BDF3),
    success: Color(0xFFE7CA76),
    pending: Color(0xFFF2C078),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? border,
    Color? text,
    Color? muted,
    Color? info,
    Color? rescue,
    Color? success,
    Color? pending,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceSoft: surfaceSoft ?? this.surfaceSoft,
    border: border ?? this.border,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    info: info ?? this.info,
    rescue: rescue ?? this.rescue,
    success: success ?? this.success,
    pending: pending ?? this.pending,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      info: Color.lerp(info, other.info, t)!,
      rescue: Color.lerp(rescue, other.rescue, t)!,
      success: Color.lerp(success, other.success, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
    );
  }
}

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
        onPrimary: dark ? const Color(0xFF33280C) : Colors.white,
        secondary: p.rescue,
        surface: p.surface,
        onSurface: p.text,
        onSurfaceVariant: p.muted,
        outline: p.border,
        outlineVariant: p.border,
        error: dark ? const Color(0xFFFFA7AE) : AppColors.error,
        errorContainer: dark
            ? const Color(0xFF45262F)
            : const Color(0xFFFFEDF0),
        onErrorContainer: dark
            ? const Color(0xFFFFC4CA)
            : const Color(0xFF962633),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
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
      .apply(fontFamily: 'Roboto');
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.info, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFF4C84B),
        foregroundColor: const Color(0xFF30250D),
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 54),
        foregroundColor: p.text,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF50452C) : const Color(0xFF3B321C),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        height: 1.5,
      ),
      actionTextColor: const Color(0xFFFFE29A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

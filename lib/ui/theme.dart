// The design's tokens (variables in mobile.pen) and the app theme. The colors
// are PowerPilot's dashboard colors.
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const page = Color(0xFFF3F5F8);
  static const card = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF6F8FB);
  static const border = Color(0xFFE2E7EE);
  static const hairline = Color(0xFFEBEFF4);
  static const ink = Color(0xFF0F1B3D);
  static const ink2 = Color(0xFF45526E);
  static const ink3 = Color(0xFF7C879C);
  static const primary = Color(0xFF2563EB);
  static const primaryWash = Color(0x142563EB);
  static const series = Color(0xFF2A78D6);
  static const seriesBar = Color(0x662A78D6);
  static const good = Color(0xFF0CA30C);
  static const goodInk = Color(0xFF0B6E1F);
  static const goodWash = Color(0x1A0CA30C);
  static const goodBar = Color(0x660CA30C);
  static const warning = Color(0xFFFAB219);
  static const warnInk = Color(0xFF8A5300);
  static const warnWash = Color(0x29FAB219);
  static const critical = Color(0xFFD03B3B);
  static const badInk = Color(0xFFB42318);
  static const badWash = Color(0x1AD03B3B);
}

/// A status color set: the wash behind an icon, the icon, and text.
enum Tone {
  good(AppColors.goodWash, AppColors.good, AppColors.goodInk),
  warn(AppColors.warnWash, AppColors.warnInk, AppColors.warnInk),
  bad(AppColors.badWash, AppColors.critical, AppColors.badInk),
  info(AppColors.primaryWash, AppColors.primary, AppColors.primary),
  neutral(AppColors.surface2, AppColors.ink3, AppColors.ink3);

  const Tone(this.wash, this.icon, this.ink);
  final Color wash, icon, ink;
}

const radius = 20.0;

/// Inter at the design's sizes. The design's 650 weight rounds to 600: the
/// bundled Inter has 400, 500, 600 and 700.
TextStyle text(double size, {FontWeight weight = FontWeight.w400, Color color = AppColors.ink, double? spacing, double? height}) =>
    TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing, height: height);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, surface: AppColors.card, primary: AppColors.primary);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.page,
    splashFactory: InkRipple.splashFactory,
    dividerColor: AppColors.hairline,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: text(14, weight: FontWeight.w500, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      titleTextStyle: text(18, weight: FontWeight.w700),
      contentTextStyle: text(14, color: AppColors.ink2, height: 1.45),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.border,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: text(15, weight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      hintStyle: text(14, color: AppColors.ink3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
  );
}

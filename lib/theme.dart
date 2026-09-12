import 'package:flutter/material.dart';

/// HiMusic 全局配色。
///
/// 数值与历史版本保持一致，集中管理以消除跨文件重复的字面量。
abstract final class AppColors {
  static const accent = Color(0xffb7d89c);
  static const background = Color(0xff0f1512);
  static const surface = Color(0xff131a16);
  static const surfaceRaised = Color(0xff1b241e);
  static const divider = Color(0xff273029);
  static const muted = Color(0xff98a198);
  static const field = Color(0xff1a211d);
  static const focus = Color(0xff34432f);
  static const sidebar = Color(0xff111814);
  static const selectedRow = Color(0xff182219);
  static const rowFocus = Color(0xff223021);
}

ThemeData buildAppTheme() => ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  fontFamily: '.AppleSystemUIFont',
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
    surface: AppColors.surface,
  ),
  dividerColor: AppColors.divider,
  focusColor: AppColors.focus,
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.field,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
  sliderTheme: const SliderThemeData(
    trackHeight: 2,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
  ),
);

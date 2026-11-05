import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 먹로그 팔레트. 노포의 미색 종이 메뉴판 + 숯불 주황 하나.
/// 화면 바탕은 따뜻한 중립색이고, 색은 얼굴 핀·단골 도장·신뢰 온도에만 쓴다.
abstract final class Palette {
  // 따뜻한 종이 톤 중립 램프
  static const page = Color(0xFFF7F2EA);
  static const card = Color(0xFFFDFAF5);
  static const raised = Color(0xFFEFE7DB);
  static const ink = Color(0xFF1F1A15); // 본문
  static const inkSoft = Color(0xFF5E544A); // 보조
  static const inkMuted = Color(0xFF7B7166); // 메타·캡션
  static const hairline = Color(0x141F1A15); // ink 8%

  // 숯불 주황. 흰 글씨 대비 4.5:1 이상
  static const ember = Color(0xFFC2461A);

  // 내 위치 점. 지도 앱에서 익숙한 파란 점을 그대로 쓴다 (이 의미로만 사용)
  static const myLocation = Color(0xFF2F6FEB);

  // 지도 바탕 (임시 지도)
  static const mapPaper = Color(0xFFF1EADF);
  static const mapStreet = Color(0xFFE5DBCC);
}

const tabular = [FontFeature.tabularFigures()];

const _ease = Cubic(0.22, 1, 0.36, 1);
const motionFast = Duration(milliseconds: 160);
const motionCurve = _ease;

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Palette.ember,
    onPrimary: Colors.white,
    secondary: Palette.ink,
    onSecondary: Colors.white,
    tertiary: Palette.inkSoft,
    onTertiary: Colors.white,
    error: Color(0xFFDC2626),
    onError: Colors.white,
    surface: Palette.page,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.inkSoft,
    surfaceContainerLowest: Palette.card,
    surfaceContainerLow: Palette.card,
    surfaceContainer: Palette.card,
    surfaceContainerHigh: Palette.raised,
    surfaceContainerHighest: Palette.raised,
    outline: Palette.inkMuted,
    outlineVariant: Palette.hairline,
    surfaceTint: Colors.transparent,
  );

  final base = GoogleFonts.ibmPlexSansKrTextTheme();
  TextStyle t(TextStyle? s, double size, double height, FontWeight w, Color c) =>
      (s ?? const TextStyle()).copyWith(fontSize: size, height: height / size, fontWeight: w, color: c, letterSpacing: 0);

  final text = base.copyWith(
    displaySmall: t(base.displaySmall, 32, 36, FontWeight.w500, Palette.ink),
    headlineSmall: t(base.headlineSmall, 22, 28, FontWeight.w500, Palette.ink),
    titleLarge: t(base.titleLarge, 18, 24, FontWeight.w500, Palette.ink),
    titleMedium: t(base.titleMedium, 16, 22, FontWeight.w500, Palette.ink),
    titleSmall: t(base.titleSmall, 14, 20, FontWeight.w500, Palette.ink),
    bodyLarge: t(base.bodyLarge, 15, 22, FontWeight.w400, Palette.ink),
    bodyMedium: t(base.bodyMedium, 14, 20, FontWeight.w400, Palette.inkSoft),
    bodySmall: t(base.bodySmall, 12, 16, FontWeight.w400, Palette.inkMuted),
    labelLarge: t(base.labelLarge, 14, 20, FontWeight.w500, Palette.ink),
    labelMedium: t(base.labelMedium, 12, 16, FontWeight.w500, Palette.inkSoft),
  );

  final hairlineSide = const BorderSide(color: Palette.hairline);
  final radius10 = BorderRadius.circular(10);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: Palette.page,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: const DividerThemeData(color: Palette.hairline, thickness: 1, space: 32),
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.page,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: const IconThemeData(color: Palette.ink, size: 20),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Palette.raised,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium!.copyWith(
            color: s.contains(WidgetState.selected) ? Palette.ink : Palette.inkMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 20,
            color: s.contains(WidgetState.selected) ? Palette.ink : Palette.inkMuted,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Palette.card,
      indicatorColor: Palette.raised,
      minWidth: 88,
      selectedIconTheme: const IconThemeData(size: 20, color: Palette.ink),
      unselectedIconTheme: const IconThemeData(size: 20, color: Palette.inkMuted),
      selectedLabelTextStyle: text.labelMedium!.copyWith(color: Palette.ink),
      unselectedLabelTextStyle: text.labelMedium!.copyWith(color: Palette.inkMuted),
    ),
    cardTheme: CardThemeData(
      color: Palette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: hairlineSide),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodyMedium,
      iconColor: Palette.inkMuted,
      selectedColor: Palette.ink,
      selectedTileColor: Palette.raised,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Palette.card,
      selectedColor: Palette.raised,
      side: hairlineSide,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: text.labelLarge!.copyWith(color: Palette.inkSoft),
      secondaryLabelStyle: text.labelLarge!.copyWith(color: Palette.ink),
      checkmarkColor: Palette.ember,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Palette.raised,
        disabledForegroundColor: Palette.inkMuted,
        minimumSize: const Size(64, 48),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.ink,
        backgroundColor: Palette.card,
        minimumSize: const Size(64, 44),
        side: hairlineSide,
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Palette.ink,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Palette.raised : Palette.card),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Palette.ink : Palette.inkSoft),
        side: WidgetStatePropertyAll(hairlineSide),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius10)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      hintStyle: text.bodyMedium!.copyWith(color: Palette.inkMuted),
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: radius10, borderSide: hairlineSide),
      enabledBorder: OutlineInputBorder(borderRadius: radius10, borderSide: hairlineSide),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius10, borderSide: const BorderSide(color: Palette.inkSoft)),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.ember,
      inactiveTrackColor: Palette.raised,
      thumbColor: Palette.ember,
      trackHeight: 4,
      overlayColor: Color(0x14C2461A),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.inkSoft,
      linearTrackColor: Palette.raised,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Palette.ember : Colors.transparent),
      side: const BorderSide(color: Palette.inkMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Palette.ink,
      unselectedLabelColor: Palette.inkMuted,
      labelStyle: text.labelLarge,
      indicatorColor: Palette.ink,
      dividerColor: Palette.hairline,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.ink,
      contentTextStyle: text.bodyMedium!.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius10),
    ),
  );
}

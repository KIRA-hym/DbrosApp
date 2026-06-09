import 'package:flutter/material.dart';

class AppTheme {
  // 공통 폰트 지정
  static const String fontFamily = 'GmarketSans';

  // 다크 테마
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFF121418),
      primaryColor: const Color(0xFFFFC700),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFC700),
        surface: const Color(0xFF1F222A),
        surfaceContainerHighest: Color(0xFF2C2F38), // divider or border color
        onSurface: Colors.white,
        error: Color(0xFFFF5252),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: const Color(0xFF1F222A),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF121418),
        selectedItemColor: Color(0xFFFFC700),
        unselectedItemColor: Color(0xFF6E717C),
      ),
      dividerColor: const Color(0xFF2C2F38),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2C2F38),
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1F222A),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Color(0xFF2C2F38)),
        ),
      ),
    );
  }

  // 라이트 테마
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      primaryColor: const Color(0xFFF59E0B), // 약간 더 진한 노란/주황 계열
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFF59E0B),
        surface: Color(0xFFFFFFFF),
        surfaceContainerHighest: Color(0xFFE5E7EB),
        onSurface: Color(0xFF1F2937),
        error: Color(0xFFEF4444),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Color(0xFF1F2937),
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: Color(0xFF1F2937)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        selectedItemColor: Color(0xFFF59E0B),
        unselectedItemColor: Color(0xFF9CA3AF),
      ),
      dividerColor: const Color(0xFFE5E7EB),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E7EB),
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 2,
        shadowColor: const Color(0x11000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
    );
  }
}

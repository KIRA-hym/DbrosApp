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

  // AMOLED 블랙 테마
  static ThemeData get amoledTheme {
    return ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: Colors.black,
      primaryColor: const Color(0xFFFFC700),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFC700),
        surface: Colors.black,
        surfaceContainerHighest: Color(0xFF2C2F38), // divider or border color
        onSurface: Colors.white,
        error: Color(0xFFFF5252),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
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
        backgroundColor: Colors.black,
        selectedItemColor: Color(0xFFFFC700),
        unselectedItemColor: Color(0xFF6E717C),
      ),
      dividerColor: const Color(0xFF2C2F38),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2C2F38),
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Color(0xFF2C2F38)),
        ),
      ),
    );
  }

  // 라이트 테마 (대안 A: 블랙 & 골드)
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFFF0F2F5), // 더 또렷한 연그레이
      primaryColor: const Color(0xFFF59E0B), // 골드 톤 유지
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFF59E0B),
        onPrimary: Color(0xFF000000), // 골드 위에는 검정 글씨
        surface: Color(0xFFFFFFFF),
        surfaceContainerHighest: Color(0xFFD1D5DB),
        onSurface: Color(0xFF111827), // 기본 텍스트를 거의 검정으로 대비 강화
        error: Color(0xFFEF4444),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF111827)),
        bodyMedium: TextStyle(color: Color(0xFF111827)),
        bodySmall: TextStyle(color: Color(0xFF4B5563)),
        titleLarge: TextStyle(color: Color(0xFF111827)),
        titleMedium: TextStyle(color: Color(0xFF111827)),
        titleSmall: TextStyle(color: Color(0xFF111827)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: Color(0xFF000000), // 블랙 타이틀
          fontWeight: FontWeight.w900,
        ),
        iconTheme: IconThemeData(color: Color(0xFF000000)), // 블랙 아이콘
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        selectedItemColor: Color(0xFF111827), // 활성화 아이콘 완전 블랙
        unselectedItemColor: Color(0xFF9CA3AF),
      ),
      dividerColor: const Color(0xFFD1D5DB), // 선명한 경계선
      dividerTheme: const DividerThemeData(
        color: Color(0xFFD1D5DB),
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 2,
        shadowColor: const Color(0x0C000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Color(0xFFD1D5DB)), // 명확한 보더
        ),
      ),
    );
  }
}

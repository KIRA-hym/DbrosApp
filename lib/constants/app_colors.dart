import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 색상 상수.
/// 하드코딩된 Color 리터럴 대신 이 상수를 참조하세요.
class AppColors {
  AppColors._();

  // ── 기본 팔레트 ──────────────────────────────────────────────
  /// 주요 강조색 (골드)
  static const Color primary = Color(0xFFFFC700);

  /// Scaffold / 전체 배경
  static const Color background = Color(0xFF121418);

  /// 카드, AppBar 표면색
  static const Color surface = Color(0xFF1F222A);

  /// 홈 요약 셀 등 더 어두운 표면
  static const Color surfaceDeep = Color(0xFF16181D);

  /// 구분선, 테두리
  static const Color divider = Color(0xFF2C2F38);

  // ── 텍스트 ───────────────────────────────────────────────────
  /// 보조 텍스트 (레이블, 힌트 등)
  static const Color textSecondary = Color(0xFF6E717C);

  // ── 기능 색상 (Semantic Colors) ──────────────────────────────
  /// 수입 표시 — 앱 전체 통일
  static const Color income = Colors.lightBlueAccent;

  /// 지출 표시
  static const Color expense = Color(0xFFFF5252);

  /// 순익 표시 (primary와 동일, 명시적 의미 부여)
  static const Color net = Color(0xFFFFC700);

  // ── 기타 기능 색상 ────────────────────────────────────────────
  /// 백업/내보내기 버튼
  static const Color exportAction = Color(0xFF4CAF50);

  /// 복원/가져오기 버튼
  static const Color importAction = Color(0xFF2196F3);
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 폰 · 태블릿 · 폴드 펼침(넓은 화면) 구간.
enum LayoutTier {
  compact,
  phone,
  tablet,
  expanded,
}

/// 폴드 펼침·가로·넓은 뷰포트(웹 미리보기 포함) 레이아웃.
class ResponsiveLayout {
  ResponsiveLayout._();

  /// 펼침·폴드 내부 화면 또는 **가로 회전** 시 넓은 레이아웃(마스터·디테일 등) 사용.
  static bool qualifiesAsExpanded(Size size) {
    final w = size.width;
    final h = size.height;
    final shortest = math.min(w, h);
    final longest = math.max(w, h);
    // Z Fold 6 펼침 세로(~690×830dp) · 웹 창을 넓힐 때
    if (w >= 720 || (shortest >= 560 && longest >= 680)) {
      return true;
    }
    // 가로 모드(일반 폰·에뮬레이터)
    if (w > h && longest >= 600 && shortest >= 320) {
      return true;
    }
    return false;
  }

  static bool isLandscape(Size size) => size.width > size.height;

  static LayoutTier tierOf(Size size) {
    if (qualifiesAsExpanded(size)) {
      return LayoutTier.expanded;
    }
    final w = size.width;
    if (w >= 600) return LayoutTier.tablet;
    if (w < 360) return LayoutTier.compact;
    return LayoutTier.phone;
  }

  static LayoutTier tier(BuildContext context) => tierOf(MediaQuery.sizeOf(context));

  static bool isTablet(BuildContext context) =>
      tier(context).index >= LayoutTier.tablet.index;

  static bool isExpanded(BuildContext context) => tier(context) == LayoutTier.expanded;

  /// 접힌 폰·세로 일반 화면(2×2·단일 컬럼 등).
  static bool isPhoneLayout(BuildContext context) => !isExpanded(context);

  /// 통계 화면 「전체 통계」「수익 분석」 등 섹션 제목과 동일한 논리 크기.
  /// (실제 표시는 [MediaQuery] 텍스트 스케일이 추가 적용됨 — [FontSizeService]와 동일)
  static double sectionTitleFontSize(BuildContext context) =>
      isTablet(context) ? 18.0 : 16.0;

  static TextStyle sectionTitleTextStyle(
    BuildContext context, {
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return TextStyle(
      fontFamily: 'GmarketSans',
      color: color,
      fontWeight: fontWeight,
      fontSize: sectionTitleFontSize(context),
      height: 1.12,
    );
  }

  /// [MediaQuery.textScaler] 반영 크기 — 고정 높이 레이아웃 계산용.
  static double layoutFontSize(BuildContext context, double logicalSize) =>
      MediaQuery.textScalerOf(context).scale(logicalSize);

  /// 홈·통계 2×2 요약 칸 표시값(제목은 [sectionTitleFontSize]).
  static double summaryValueFontSize(BuildContext context) =>
      isTablet(context) ? 15.0 : 14.0;

  static TextStyle summaryValueTextStyle(
    BuildContext context, {
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return TextStyle(
      fontFamily: 'GmarketSans',
      color: color,
      fontWeight: fontWeight,
      fontSize: summaryValueFontSize(context),
      height: 1.12,
    );
  }

  /// 본문 최대 너비(가운데 정렬용).
  static double contentMaxWidth(Size size) {
    switch (tierOf(size)) {
      case LayoutTier.expanded:
        return 960;
      case LayoutTier.tablet:
        return 720;
      default:
        return size.width;
    }
  }

  /// 작성·설정 폼 최대 너비.
  static double formMaxWidth(Size size) {
    switch (tierOf(size)) {
      case LayoutTier.expanded:
        return 720;
      case LayoutTier.tablet:
        return 600;
      default:
        return size.width;
    }
  }

  static double horizontalPadding(BuildContext context) {
    switch (tier(context)) {
      case LayoutTier.expanded:
        return 28;
      case LayoutTier.tablet:
        return 24;
      case LayoutTier.compact:
        return 16;
      case LayoutTier.phone:
        return 20;
    }
  }

  /// 날짜 스크롤 등 바텀시트 — 짧은 화면에서 고정 높이 overflow 방지.
  static double bottomSheetHeight(
    BuildContext context, {
    double fraction = 0.55,
    double maxHeight = 420,
    double minHeight = 280,
  }) {
    final h = MediaQuery.sizeOf(context).height;
    return math.max(minHeight, math.min(maxHeight, h * fraction));
  }
}

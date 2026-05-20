import 'package:flutter/material.dart';

/// 폰 · 태블릿 · 폴드 펼침(넓은 화면) 구간.
enum LayoutTier {
  compact,
  phone,
  tablet,
  expanded,
}

/// Galaxy Fold 등 넓은 내부 화면·태블릿 대응.
class ResponsiveLayout {
  ResponsiveLayout._();

  static LayoutTier tierOf(Size size) {
    final w = size.width;
    final shortest = size.shortestSide;
    // Z Fold 6 펼침: 가로 ~840dp 이상 또는 짧은 변 ≥580 & 가로 ≥720
    if (w >= 840 || (shortest >= 580 && w >= 720)) {
      return LayoutTier.expanded;
    }
    if (w >= 600) return LayoutTier.tablet;
    if (w < 360) return LayoutTier.compact;
    return LayoutTier.phone;
  }

  static LayoutTier tier(BuildContext context) => tierOf(MediaQuery.sizeOf(context));

  static bool isTablet(BuildContext context) =>
      tier(context).index >= LayoutTier.tablet.index;

  static bool isExpanded(BuildContext context) => tier(context) == LayoutTier.expanded;

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
}

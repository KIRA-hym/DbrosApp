import 'dart:math' as math;

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

  /// 펼침·태블릿·폴드 내부 화면 또는 **가로 회전** 시 넓은 레이아웃(마스터·디테일 등) 사용.
  static bool qualifiesAsExpanded(Size size) {
    final w = size.width;
    final h = size.height;
    final shortest = math.min(w, h);
    final longest = math.max(w, h);
    // Z Fold 6 펼침 세로(~690×830dp): 짧은 변 ≥580 & 긴 변 ≥720, 또는 가로 ≥840
    if (w >= 840 || (shortest >= 580 && longest >= 720)) {
      return true;
    }
    // 단말기 가로 모드: 긴 변이 일반 폰 가로 폭 이상이면 펼침과 동일 레이아웃
    if (w > h && longest >= 640 && shortest >= 320) {
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

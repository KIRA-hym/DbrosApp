import 'package:flutter/material.dart';

/// 폴더블 및 태블릿 적응형 레이아웃 유틸리티
class ResponsiveLayout {
  ResponsiveLayout._();

  /// 모바일과 펼친 폴드/태블릿을 구분하는 기준 너비 (dp)
  static const double breakpoint = 600.0;
  
  /// 본문 폼, 버튼 등이 팽창할 수 있는 최대 너비
  static const double maxContentWidth = 600.0;

  /// 펼친 화면 (Fold Unfolded, Tablet, Web)
  static bool isFoldOrTablet(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= breakpoint;
  }

  /// 접힌 화면 (Mobile)
  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < breakpoint;
  }

  /// 좌우 기본 여백
  static double horizontalPadding(BuildContext context) {
    return isFoldOrTablet(context) ? 24.0 : 16.0;
  }

  /// [MediaQuery.textScaler] 반영 크기 (고정 높이 계산 등에 유지)
  static double layoutFontSize(BuildContext context, double logicalSize) =>
      MediaQuery.textScalerOf(context).scale(logicalSize);

  static double sectionTitleFontSize(BuildContext context) => 16.0;

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

  static double summaryValueFontSize(BuildContext context) => 14.0;

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

  /// 바텀시트 최대/최소 높이 제한
  static double bottomSheetHeight(
    BuildContext context, {
    double fraction = 0.55,
    double maxHeight = 420,
    double minHeight = 280,
  }) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * fraction).clamp(minHeight, maxHeight);
  }

  // --- 기존 코드와의 호환성을 위한 Stub 메서드들 ---
  static bool isTablet(BuildContext context) => isFoldOrTablet(context);
  static bool isExpanded(BuildContext context) => isFoldOrTablet(context);
  static bool isPhoneLayout(BuildContext context) => isMobile(context);
  static double formMaxWidth(Size size) => maxContentWidth;
  static double contentMaxWidth(Size size) => maxContentWidth;
}

/// 화면 너비가 넓을 때 자식 위젯이 무한정 늘어나는 것을 방지하고 가운데 정렬하는 래퍼 위젯.
class AdaptiveMaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AdaptiveMaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = ResponsiveLayout.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

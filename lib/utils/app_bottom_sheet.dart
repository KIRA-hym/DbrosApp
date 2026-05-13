import 'package:flutter/material.dart';

import '../main_navigation.dart';

/// 하단 탭·시스템 내비게이션 위에 뜨도록 여백을 맞춘 모달 바텀시트.
class AppBottomSheet {
  AppBottomSheet._();

  static const double _copyrightBandHeight = 24;

  static double chromePadding(BuildContext context) {
    final system = MediaQuery.viewPaddingOf(context).bottom;
    if (MainTabScope.maybeOf(context) == null) {
      return system;
    }
    return system + _copyrightBandHeight + kBottomNavigationBarHeight;
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    Color? backgroundColor,
    ShapeBorder? shape,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useRootNavigator: false,
      backgroundColor: backgroundColor,
      shape: shape,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: chromePadding(sheetContext)),
          child: builder(sheetContext),
        );
      },
    );
  }
}

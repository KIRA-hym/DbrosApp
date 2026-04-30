import 'package:flutter/material.dart';

/// 하단 탭(MainWrapper) 전환용. 작성 탭 등 임베드 화면에서 목록 등으로 안전하게 이동할 때 사용합니다.
class MainTabScope extends InheritedWidget {
  final void Function(int index) selectTab;

  const MainTabScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  /// 탭 전환만 호출할 때 사용 (의존 등록 없음).
  static MainTabScope? maybeOf(BuildContext context) {
    return context.findAncestorWidgetOfExactType<MainTabScope>();
  }

  @override
  bool updateShouldNotify(MainTabScope oldWidget) => false;
}

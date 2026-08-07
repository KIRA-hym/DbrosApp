import 'package:flutter/foundation.dart';

class FormStateProvider {
  /// 운행일지 폼의 변경(Dirty) 상태를 전역으로 관리.
  /// 네비게이션 탭 이동 시 이 값이 true면 이탈 경고를 띄우기 위해 사용.
  static final ValueNotifier<bool> isWriteFormDirtyNotifier = ValueNotifier(false);
}

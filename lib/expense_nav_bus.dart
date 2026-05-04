/// [ExpenseMainWrapper]가 등록하고, 상세 등 푸시된 화면에서 탭 전환에 사용합니다.
class ExpenseNavBus {
  static void Function(int)? _selectTab;

  static void register(void Function(int) fn) {
    _selectTab = fn;
  }

  static void unregister(void Function(int) fn) {
    if (_selectTab == fn) _selectTab = null;
  }

  static void goToTab(int index) => _selectTab?.call(index);
}

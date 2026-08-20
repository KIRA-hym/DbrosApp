import 'dart:io';

void main() {
  // 1. settings_page.dart 수정 (수수료/보험료 패딩 분리)
  final settingsFile = File('lib/screens/settings_page.dart');
  String settingsCode = settingsFile.readAsStringSync();
  
  final oldFeeInsuranceStr = '''      Container(
        key: _keyFeeInsurance,
        child: Column(
          children: [
            _buildListManageButton(
              title: '수수료 설정',
              icon: Icons.monetization_on_outlined,
              onTap: _showFeeDialog,
            ),
            _buildListManageButton(
              title: '보험료 설정',
              icon: Icons.shield_outlined,
              onTap: _showInsuranceDialog,
            ),
          ],
        ),
      ),''';
      
  final newFeeInsuranceStr = '''      Container(
        key: _keyFeeInsurance,
        child: _buildListManageButton(
          title: '수수료 설정',
          icon: Icons.monetization_on_outlined,
          onTap: _showFeeDialog,
        ),
      ),
      _buildListManageButton(
        title: '보험료 설정',
        icon: Icons.shield_outlined,
        onTap: _showInsuranceDialog,
      ),''';

  if (settingsCode.contains(oldFeeInsuranceStr)) {
    settingsCode = settingsCode.replaceFirst(oldFeeInsuranceStr, newFeeInsuranceStr);
    settingsFile.writeAsStringSync(settingsCode);
    print('Updated settings_page.dart');
  } else {
    print('Could not find fee/insurance block in settings_page.dart');
  }

  // 2. list_manage_dialog.dart 수정 (드래그 핸들 노란색)
  final listDialogFile = File('lib/widgets/list_manage_dialog.dart');
  String listDialogCode = listDialogFile.readAsStringSync();
  
  final oldDragIcon = 'Icon(Icons.drag_handle, color: Theme.of(context).dividerColor, size: 20)';
  final newDragIcon = 'Icon(Icons.drag_handle, color: const Color(0xFFFFC700), size: 20)';
  
  if (listDialogCode.contains(oldDragIcon)) {
    listDialogCode = listDialogCode.replaceFirst(oldDragIcon, newDragIcon);
    listDialogFile.writeAsStringSync(listDialogCode);
    print('Updated list_manage_dialog.dart');
  } else {
    print('Could not find drag_handle in list_manage_dialog.dart');
  }
}

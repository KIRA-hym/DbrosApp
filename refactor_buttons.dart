import 'dart:io';

void main() {
  final file = File('lib/screens/settings_page.dart');
  String code = file.readAsStringSync();

  // 1. Coordinate sharing
  code = code.replaceFirst(
    "GlassDialogConfirmButton(\n                          label: '전송하기',",
    "GlassDialogConfirmButton(\n                          label: '전송하기',\n                          filled: true,"
  );

  // 2. Image cleanup
  code = code.replaceFirst(
    "GlassDialogConfirmButton(\n                            label: '지금 정리',",
    "GlassDialogConfirmButton(\n                            label: '지금 정리',\n                            filled: true,"
  );

  // 3. Ad reward
  code = code.replaceFirst(
    "GlassDialogConfirmButton(\n              label: '시청하기',",
    "GlassDialogConfirmButton(\n              label: '시청하기',\n              filled: true,"
  );

  file.writeAsStringSync(code);
  print("Updated settings_page buttons to filled: true");
}

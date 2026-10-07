import 'dart:io';

void main() {
  final file = File('lib/utils/logi_colmanner_ocr.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst('if (amounts.isEmpty) return null;', 'print(\'DEBUG amounts: \$amounts\');\n    if (amounts.isEmpty) return null;');
  file.writeAsStringSync(content);
}

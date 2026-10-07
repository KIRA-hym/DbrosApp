import 'dart:io';

void main() {
  final file = File('lib/utils/logi_colmanner_ocr.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst('if (!inSection) continue;', 'if (!inSection) continue;\n        print(\'DEBUG line: \$trimmed\');');
  content = content.replaceFirst('amounts.add(v);', 'print(\'DEBUG ADDED \$v\');\n          amounts.add(v);');
  file.writeAsStringSync(content);
}

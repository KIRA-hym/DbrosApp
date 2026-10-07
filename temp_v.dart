import 'dart:io';

void main() {
  final file = File('lib/utils/logi_colmanner_ocr.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst(
    'if (v != null && v >= 1000 && v <= 999_999 && !amounts.contains(v)) {', 
    'print(\'V VALUE: \$v\');\n        if (v != null && v >= 1000 && v <= 999_999 && !amounts.contains(v)) {'
  );
  file.writeAsStringSync(content);
}

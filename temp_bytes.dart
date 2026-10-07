import 'dart:io';

void main() {
  final file = File('lib/utils/logi_colmanner_ocr.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst(
    'final v = _strictFareDigitsFromLine(trimmed) ?? parseLogiFareFromOcrText(trimmed);', 
    'print(\'TRIMMED BYTES: \${trimmed.codeUnits}\'); final v = _strictFareDigitsFromLine(trimmed) ?? parseLogiFareFromOcrText(trimmed);'
  );
  file.writeAsStringSync(content);
}

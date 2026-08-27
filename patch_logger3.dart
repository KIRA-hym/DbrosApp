import 'dart:io';

void main() {
  var file = File('lib/services/ocr_error_logger.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(r'\$', r'$');
  file.writeAsStringSync(content);
}

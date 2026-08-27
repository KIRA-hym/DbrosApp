import 'dart:io';

void main() {
  var file = File('lib/services/ocr_error_logger.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll("'unified_upload_count_'", "'unified_upload_count_\$todayStr'");
  file.writeAsStringSync(content);
}

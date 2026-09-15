import 'dart:io';

void main() {
  final file = File('lib/services/ocr_error_logger.dart');
  var text = file.readAsStringSync();
  
  text = text.replaceAll(
    "'error_upload_count_'",
    "'error_upload_count_\'"
  );

  file.writeAsStringSync(text);
}
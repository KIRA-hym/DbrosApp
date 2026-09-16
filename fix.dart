
import 'dart:io';
void main() {
  final file = File('lib/services/call_card_ocr_parse_service.dart');
  var lines = file.readAsLinesSync();
  lines = lines.where((line) => !line.contains('smart_ocr_service.dart')).toList();
  lines = lines.map((line) {
    if (line.contains('return await SmartOcrService.enhance(')) {
      return '    return logData;';
    }
    return line;
  }).toList();
  file.writeAsStringSync(lines.join('\n'));
}


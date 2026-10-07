import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  // Use reflection or just copy the logic to test
  var line = '155000';
  var t = line.trim().replaceAll(',', '').replaceAll(RegExp(r'\\s'), '');
  t = t.replaceAll(RegExp(r'[!]+'), '').replaceAll(RegExp(r'[원₩lL|I]+'), '');
  print('t: \$t');
  var match = RegExp(r'^\\d{4,6}\$').hasMatch(t);
  print('isStrict: \$match');
}

import 'dart:io';
void main() {
  final f = File('lib/utils/tmap_trip_detail_ocr.dart');
  var text = f.readAsStringSync();
  text = text.replaceFirst('    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---', '    if (startAddress.contains(\'\\uC6B4\\uD589\\uC77C\\uC790\') || startAddress.contains(\'\\uC6B4\\uD589\\uBC88\\uD638\') || startAddress.contains(\'\\uC694\\uAE30\\uC694\')) startAddress = \\'\\';\\n    if (endAddress.contains(\'\\uC6B4\\uD589\\uC77C\\uC790\') || endAddress.contains(\'\\uC6B4\\uD589\\uBC88\\uD638\') || endAddress.contains(\'\\uC694\\uAE30\\uC694\')) endAddress = \\'\\';\\n\\n    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---');
  text = text.replaceFirst(r\"RegExp(r'\\uC6B4\\uD589\\uC77C\\uC790\\s*(\\d{4})[.\\\\-](\\d{1,2})[.\\\\-](\\d{1,2}).*?(\\d{2}:\\d{2})\\s*~')\", r\"RegExp(r'\\uC6B4\\uD589\\uC77C\\uC790\\s*(\\d{4})\\s*[.\\\\-\\uB144]\\s*(\\d{1,2})\\s*[.\\\\-\\uC6D4]\\s*(\\d{1,2}).*?(\\d{2}\\s*:\\s*\\d{2})\\s*~')\");
  text = text.replaceFirst('driveStartTimeHm = dtMatch.group(4)!;', 'driveStartTimeHm = dtMatch.group(4)!.replaceAll(\\' \\', \\'\\');');
  f.writeAsStringSync(text);
}
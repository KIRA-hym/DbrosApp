import 'dart:io';
void main() {
  final f = File('lib/utils/tmap_trip_detail_ocr.dart');
  var t = f.readAsStringSync();
  t = t.replaceFirst(
    'if (startAddress.isEmpty || endAddress.isEmpty) {\n      final lines = normalized.split',
    'if (startAddress.contains("운행일자") || startAddress.contains("운행첈호") || startAddress.contains("요기요")) startAddress = \"\";\n    if (endAddress.contains("운행일자") || endAddress.contains("운행첈호") || endAddress.contains("요기요")) endAddress = \"\";\n\n    if (startAddress.isEmpty || endAddress.isEmpty) {\n      final lines = normalized.split'
  );
  t = t.replaceFirst(
    r'[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~',
    r'\s*[.\-년]\s*(\d{1,2})\s*[.\-딌]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~'
  );
  t = t.replaceFirst(
    'driveStartTimeHm = dtMatch.group(4)!;',
    "driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');"
  );
  f.writeAsStringSync(t);
  print('Done');
}
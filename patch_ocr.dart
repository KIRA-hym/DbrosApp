import 'dart:io';

void main() {
  final file = File('lib/utils/tmap_trip_detail_ocr.dart');
  String text = file.readAsStringSync();

  // 1. Fix vertical parser fallback logic to first clear false positives
  text = text.replaceFirst(
    '// --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---',
    '''
    // Clear false positives from horizontal parsing
    if (startAddress.contains('款青老磊') || startAddress.contains('款青锅龋') || startAddress.contains('夸扁夸')) startAddress = '';
    if (endAddress.contains('款青老磊') || endAddress.contains('款青锅龋') || endAddress.contains('夸扁夸')) endAddress = '';

    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---'''
  );

  // 2. Fix date regex to allow spaces around dots
  text = text.replaceFirst(
    r"final dtMatch = RegExp(r'款青老磊\s*(\d{4})[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~').firstMatch(flat);",
    r"final dtMatch = RegExp(r'款青老磊\s*(\d{4})\s*[.\-斥]\s*(\d{1,2})\s*[.\-岿]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~').firstMatch(flat);"
  );
  
  // 3. Fix time extraction (removing spaces in time)
  text = text.replaceFirst(
    "driveStartTimeHm = dtMatch.group(4)!;",
    "driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');"
  );

  file.writeAsStringSync(text);
  print('Patched successfully');
}

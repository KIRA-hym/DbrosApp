import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('Colmanner Missing Address Test', () {
    final file = File(r'C:\dbros_app\test\colmanner_test.txt');
    final text = file.readAsStringSync();
    
    final parsed = LogiColmannerOcr.parseColmanner(text);
    print('--- OCR Parsing Result ---');
    print('Start Loc: ${parsed.startLocation}');
    print('End Loc: ${parsed.endLocation}');
    print('Waypoint: ${parsed.waypoint}');
  });
}

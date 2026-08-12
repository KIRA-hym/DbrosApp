import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('Logi Colmanner OCR Parsing Test', () {
    final file = File(r'C:\Users\HYM\.gemini\antigravity\brain\fa5e9227-a130-4b62-a6de-d36f8e057889\scratch\test_logi.txt');
    final text = file.readAsStringSync();
    
    final parsed = LogiColmannerOcr.parseLogi(text);
    print('--- OCR Parsing Result ---');
    print('Gross Fare: ${parsed.grossFare}');
    print('Start Loc: ${parsed.startLocation}');
    print('End Loc: ${parsed.endLocation}');
    print('Waypoint: ${parsed.waypoint}');
    
    expect(parsed.grossFare, 55000);
  });
}

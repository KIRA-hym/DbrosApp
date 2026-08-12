import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('Colmanner Missing Address Test Final', () {
    final file = File(r'C:\dbros_app\test\colmanner_test.txt');
    final text = file.readAsStringSync();
    
    final parsed = LogiColmannerOcr.parseColmanner(text);
    print('--- FINAL PARSED ---');
    print('Start Loc: ${parsed.startLocation}');
    print('End Loc: ${parsed.endLocation}');
    print('Waypoint: ${parsed.waypoint}');
    
    expect(parsed.startLocation.contains('경기 고양시'), true);
    expect(parsed.startLocation.contains('장항제2공영주차장입구'), true);
    expect(parsed.endLocation.contains('경기 안양시'), true);
    expect(parsed.endLocation.contains('요라'), false);
  });
}

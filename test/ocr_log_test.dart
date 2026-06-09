import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'package:dbros_app/utils/tmap_call_card_ocr.dart';

void main() {
  test('OCR Log parsing test', () async {
    final file = File('work/ocr_log_sample.txt');
    if (!file.existsSync()) {
      print('File not found');
      return;
    }
    
    final lines = await file.readAsLines();
    
    String currentProgram = '';
    String currentRawOcr = '';
    bool isReadingRaw = false;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.startsWith('  프로그램:')) {
        currentProgram = line.split(':')[1].trim();
      } else if (line.contains('─ RAW OCR 텍스트 ─')) {
        isReadingRaw = true;
        currentRawOcr = '';
      } else if (line.startsWith('───────────────────────────────────────')) {
        if (isReadingRaw) {
          print('--- [TEST: $currentProgram] ---');
          try {
            if (currentProgram == '콜마너') {
              final parsed = LogiColmannerOcr.parseColmanner(currentRawOcr);
              print('Fare: ${parsed.grossFare}, Start: ${parsed.startLocation}, End: ${parsed.endLocation}, Waypoint: ${parsed.waypoint}');
            } else if (currentProgram == '로지') {
              final parsed = LogiColmannerOcr.parseLogi(currentRawOcr);
              print('Fare: ${parsed.grossFare}, Start: ${parsed.startLocation}, End: ${parsed.endLocation}, Waypoint: ${parsed.waypoint}');
            } else if (currentProgram.contains('카카오')) {
              final parsed = KakaoCallCardOcr.parse(currentRawOcr);
              print('Fare: ${parsed.grossFare}, Start: ${parsed.startLocation}, End: ${parsed.endLocation}, Waypoint: ${parsed.waypoint}');
            } else if (currentProgram == '티맵') {
              final parsed = TmapCallCardOcr.parse(currentRawOcr);
              print('Fare: ${parsed.grossFare}, Start: ${parsed.startLocation}, End: ${parsed.endLocation}, Waypoint: ${parsed.waypoint}');
            }
          } catch (e) {
            print('Error parsing: $e');
          }
          print('');
        }
        isReadingRaw = false;
      } else {
        if (isReadingRaw) {
          currentRawOcr += line + '\n';
        }
      }
    }
  });
}


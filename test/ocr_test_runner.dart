import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/kakao_call_card_ocr.dart';

void main() {
  test('OCR Log parsing test', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final file = File('work/ocr_log_sample.txt');
    final outFile = File('work/ocr_test_out.txt');
    if (!file.existsSync()) {
      print('File not found');
      return;
    }
    
    final lines = await file.readAsLines();
    final outBuffer = StringBuffer();
    
    String currentProgram = '';
    String currentRawOcr = '';
    bool isReadingRaw = false;
    int testCount = 0;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.startsWith('  프로그램:')) {
        currentProgram = line.split(':')[1].trim();
      } else if (line.contains('─ RAW OCR 텍스트 ─')) {
        isReadingRaw = true;
        currentRawOcr = '';
      } else if (line.startsWith('───────────────────────────────────────')) {
        if (isReadingRaw) {
          testCount++;
          outBuffer.writeln('--- [TEST $testCount: $currentProgram] ---');
          try {
            if (currentProgram == '콜마너') {
              final parsed = LogiColmannerOcr.parseColmanner(currentRawOcr);
              outBuffer.writeln('Fare: ' + parsed.grossFare.toString() + ', Start: ' + parsed.startLocation + ', End: ' + parsed.endLocation + ', Waypoint: ' + parsed.waypoint);
            } else if (currentProgram == '로지') {
              final parsed = LogiColmannerOcr.parseLogi(currentRawOcr);
              outBuffer.writeln('Fare: ' + parsed.grossFare.toString() + ', Start: ' + parsed.startLocation + ', End: ' + parsed.endLocation + ', Waypoint: ' + parsed.waypoint);
            } else if (currentProgram.contains('카카오')) {
              final parsed = KakaoCallCardOcr.parseScreen([], currentRawOcr);
              outBuffer.writeln('Fare: ' + parsed.grossFare.toString() + ', Start: ' + parsed.startLocation + ', End: ' + parsed.endLocation + ', Waypoint: ' + parsed.waypoint);
            } else if (currentProgram == '티맵') {
              outBuffer.writeln('Skip Tmap');
            }
          } catch (e) {
            outBuffer.writeln('Error parsing: ' + e.toString());
          }
          outBuffer.writeln('');
        }
        isReadingRaw = false;
      } else {
        if (isReadingRaw) {
          currentRawOcr += line + '\n';
        }
      }
    }
    
    await outFile.writeAsString(outBuffer.toString());
  });
}

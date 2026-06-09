import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../lib/utils/kakao_call_card_ocr.dart';
import '../lib/utils/logi_colmanner_ocr.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('OCR Expectation Test', () async {
    final file = File('work/ocr_log_sample.txt');
    if (!file.existsSync()) {
      print('File not found');
      return;
    }

    final content = await file.readAsString();
    final blocks = content.split('───────────────────────────────────────');
    
    int totalCount = 0;
    int passCount = 0;

    for (var i = 0; i < blocks.length; i++) {
      final text = blocks[i].trim();
      if (text.isEmpty) continue;
      
      final expectStart = text.indexOf('/*');
      final expectEnd = text.indexOf('*/', expectStart);
      if (expectStart == -1 || expectEnd == -1) continue;

      final expectStr = text.substring(expectStart + 2, expectEnd).trim();
      final rawStart = text.indexOf('─ RAW OCR 텍스트 ─');
      if (rawStart == -1) continue;
      final rawText = text.substring(rawStart + 15).trim();

      String program = '알 수 없음';
      if (text.contains('프로그램: 로지')) program = '로지';
      else if (text.contains('프로그램: 콜마너')) program = '콜마너';
      else if (text.contains('프로그램: 카카오')) {
        program = KakaoCallCardOcr.detectKakaoProgram(rawText) ?? '카카오(일반)';
      }

      String start = '', end = '', fareStr = '';

      if (program == '로지') {
        final res = LogiColmannerOcr.parseLogi(rawText);
        start = res.startLocation; end = res.endLocation; fareStr = res.grossFare.toString();
      } else if (program == '콜마너') {
        final res = LogiColmannerOcr.parseColmanner(rawText);
        start = res.startLocation; end = res.endLocation; fareStr = res.grossFare.toString();
      } else if (program.startsWith('카카오')) {
        final res = KakaoCallCardOcr.parseScreen([], rawText);
        start = res.startLocation; end = res.endLocation; fareStr = (res.grossFare ?? 0).toString();
      }

      String? expectedFare;
      String? expectedStart;
      String? expectedEnd;

      final lines = expectStr.split('\n');
      for (final line in lines) {
        final l = line.trim();
        if (l.contains('요금 :')) {
          expectedFare = l.split('요금 :')[1].replaceAll('원', '').replaceAll(',', '').trim();
          expectedFare = expectedFare.split(' ')[0].split('(')[0]; 
        }
        if (l.contains('출발지 :')) {
          expectedStart = l.split('출발지 :')[1].split('(')[0].trim();
        }
        if (l.contains('도착지 :')) {
          expectedEnd = l.split('도착지 :')[1].split('(')[0].trim();
        }
      }

      // 공백 무시 비교 헬퍼
      bool fuzzyMatch(String? expected, String actual) {
        if (expected == null || expected.isEmpty) return true;
        // 기대값에 쓰여있는 텍스트의 모든 공백 제거 후 실제 파싱 텍스트에 "포함"되는지 확인
        final cleanExpected = expected.replaceAll(' ', '');
        final cleanActual = actual.replaceAll(' ', '');
        return cleanActual.contains(cleanExpected);
      }

      bool fareMatch = expectedFare == null || fareStr == expectedFare;
      bool startMatch = fuzzyMatch(expectedStart, start);
      bool endMatch = fuzzyMatch(expectedEnd, end);

      if (expectedFare != null || expectedStart != null || expectedEnd != null) {
        totalCount++;
        if (fareMatch && startMatch && endMatch) {
          passCount++;
        }
      }
    }

    print('=====================================');
    print('Total Checked Tests: $totalCount');
    print('Passed (Fuzzy): $passCount');
    if (totalCount > 0) {
      print('Accuracy (Fuzzy): ${(passCount / totalCount * 100).toStringAsFixed(1)}%');
    }
    print('=====================================');
  });
}

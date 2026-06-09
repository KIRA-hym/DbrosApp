import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../lib/utils/kakao_call_card_ocr.dart';
import '../lib/utils/logi_colmanner_ocr.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Generate Full Report', () async {
    final file = File('work/ocr_log_sample.txt');
    if (!file.existsSync()) {
      print('File not found');
      return;
    }

    final content = await file.readAsString();
    final blocks = content.split('───────────────────────────────────────');
    
    final md = StringBuffer();
    md.writeln('# OCR 원본 vs 파싱 결과 전체 보고서 (현재 로직 기준)');
    md.writeln('\n`ocr_log_sample.txt`에 있는 모든 샘플에 대하여 현재 보완된 파싱 로직을 통과시킨 결과입니다. 원본 텍스트와 추출된 요금/출발지/도착지를 직접 대조해보실 수 있습니다.\n');

    for (var i = 0; i < blocks.length; i++) {
      final text = blocks[i].trim();
      if (text.isEmpty) continue;
      
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

      md.writeln('---');
      md.writeln('### 📝 TEST ${i + 1} [$program]');
      md.writeln('<details open><summary><b>[원본 OCR 텍스트 보기]</b></summary>');
      md.writeln('\n```text\n$rawText\n```\n');
      md.writeln('</details>\n');
      md.writeln('**[파싱 추출 결과]**');
      md.writeln('- **요금** : $fareStr');
      md.writeln('- **출발지** : ${start.isEmpty ? '*(없음)*' : start.replaceAll('\n', ' ')}');
      md.writeln('- **도착지** : ${end.isEmpty ? '*(없음)*' : end.replaceAll('\n', ' ')}');
      md.writeln('\n');
    }

    final reportFile = File(r'C:\Users\HYM\.gemini\antigravity\brain\97d404c9-fd70-450b-9a2e-8f8d13e1a7ac\ocr_full_verification_report.md');
    await reportFile.writeAsString(md.toString());
    print('Report generated successfully.');
  });
}

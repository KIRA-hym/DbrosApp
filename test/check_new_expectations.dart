import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/kakao_call_card_ocr.dart';
import '../lib/utils/logi_colmanner_ocr.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Update Verification Report', () async {
    final file = File(r'C:\Users\HYM\.gemini\antigravity\brain\97d404c9-fd70-450b-9a2e-8f8d13e1a7ac\ocr_full_verification_report.md');
    if (!file.existsSync()) {
      print('Report file not found');
      return;
    }

    final content = await file.readAsString();
    final blocks = content.split('---');
    
    int totalCount = 0;
    int passCount = 0;

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i].trim();
      if (!block.contains('### 📝 TEST')) continue;
      
      final titleLine = block.split('\n').firstWhere((l) => l.startsWith('### 📝 TEST'));
      String program = '알 수 없음';
      if (titleLine.contains('[로지]')) program = '로지';
      else if (titleLine.contains('[콜마너]')) program = '콜마너';
      else if (titleLine.contains('[카카오(일반)]')) program = '카카오(일반)';
      else if (titleLine.contains('[카카오(프콜)]')) program = '카카오(프콜)';
      else if (titleLine.contains('[티맵]')) program = '티맵';

      if (!block.contains('# 기대값')) continue;

      final expectStart = block.indexOf('# 기대값');
      
      // 기존 파싱 검증 결과 영역이 있다면 제거
      String cleanBlock = block;
      if (cleanBlock.contains('# 파싱 검증 결과 (최신)')) {
        cleanBlock = cleanBlock.substring(0, cleanBlock.indexOf('# 파싱 검증 결과 (최신)')).trim();
      }
      
      // 구버전 `**[파싱 추출 결과]**` 영역이 있다면 제거
      if (cleanBlock.contains('**[파싱 추출 결과]**')) {
        final startIdx = cleanBlock.indexOf('**[파싱 추출 결과]**');
        final endIdx = cleanBlock.indexOf('# 기대값', startIdx);
        if (startIdx != -1 && endIdx != -1) {
          cleanBlock = cleanBlock.substring(0, startIdx).trim() + '\n\n' + cleanBlock.substring(endIdx).trim();
        }
      }
      
      final expectStr = cleanBlock.substring(cleanBlock.indexOf('# 기대값')).trim();

      String expectedStart = '';
      String expectedEnd = '';
      String expectedFare = '';

      for (final line in expectStr.split('\n')) {
        if (line.contains('- **출발지** :')) expectedStart = line.split('- **출발지** :')[1].trim();
        if (line.contains('- **도착지** :')) expectedEnd = line.split('- **도착지** :')[1].trim();
        if (line.contains('- **요금** :')) expectedFare = line.split('- **요금** :')[1].trim();
      }

      final rawStartIdx = cleanBlock.indexOf('```text');
      final rawEndIdx = cleanBlock.indexOf('```', rawStartIdx + 7);
      if (rawStartIdx == -1 || rawEndIdx == -1) continue;

      final rawText = cleanBlock.substring(rawStartIdx + 7, rawEndIdx).trim();

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

      bool fuzzyMatch(String expected, String actual) {
        if (expected.isEmpty) return true;
        final cleanExpected = expected.replaceAll(' ', '');
        final cleanActual = actual.replaceAll(' ', '');
        return cleanExpected == cleanActual;
      }

      bool fareMatch = expectedFare.isEmpty || fareStr == expectedFare;
      bool startMatch = expectedStart.isEmpty || fuzzyMatch(expectedStart, start);
      bool endMatch = expectedEnd.isEmpty || fuzzyMatch(expectedEnd, end);

      totalCount++;
      bool passed = fareMatch && startMatch && endMatch;
      if (passed) passCount++;

      // 블록 뒷부분에 최신 결과 덧붙이기
      StringBuffer sb = StringBuffer();
      sb.writeln(cleanBlock);
      sb.writeln();
      sb.writeln('# 파싱 검증 결과 (최신)');
      sb.writeln('- [${passed ? 'x' : ' '}] 파싱 보완 필요 여부 (체크시 통과, 빈칸 시 보완 필요)');
      if (expectedStart.isNotEmpty) {
        sb.writeln('- **실제 출발지** : $start');
        sb.writeln('- **기대 출발지** : $expectedStart ${startMatch ? '(✅ 일치)' : '(❌ 불일치)'}');
      }
      if (expectedEnd.isNotEmpty) {
        sb.writeln('- **실제 도착지** : $end');
        sb.writeln('- **기대 도착지** : $expectedEnd ${endMatch ? '(✅ 일치)' : '(❌ 불일치)'}');
      }
      if (expectedFare.isNotEmpty) {
        sb.writeln('- **실제 요금** : $fareStr');
        sb.writeln('- **기대 요금** : $expectedFare ${fareMatch ? '(✅ 일치)' : '(❌ 불일치)'}');
      }
      
      blocks[i] = '\n' + sb.toString().trim() + '\n';
    }

    final newContent = blocks.join('\n---\n');
    await file.writeAsString(newContent);

    print('=====================================');
    print('Total User Expectations: $totalCount');
    print('Passed: $passCount');
    if (totalCount > 0) {
      print('Accuracy: ${(passCount / totalCount * 100).toStringAsFixed(1)}%');
    }
    print('Report successfully updated at: ${file.path}');
    print('=====================================');
  });
}

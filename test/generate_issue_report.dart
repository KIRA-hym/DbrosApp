import 'dart:io';

void main() async {
  final sampleFile = File('work/ocr_log_sample.txt');
  if (!sampleFile.existsSync()) return;
  final sampleContent = await sampleFile.readAsString();
  final sampleBlocks = sampleContent.split('───────────────────────────────────────');

  final outFile = File('work/ocr_test_out.txt');
  if (!outFile.existsSync()) return;
  final outContent = await outFile.readAsString();
  final outBlocks = outContent.split('--- [TEST ');

  final md = StringBuffer();
  md.writeln('# OCR 파싱 보완 검증 보고서 (기대값 대조)');
  md.writeln('');
  md.writeln('사용자님이 \ocr_log_sample.txt\에 작성해주신 **기대값(수정 요구사항)**이 있는 테스트 케이스들만 필터링하여, 현재 파싱 결과와 비교한 내역입니다.');
  md.writeln('기대값에서 언급되지 않은 항목(예: 도착지만 언급된 경우 요금/출발지는 정상)은 정상으로 간주되며, 이번 보완을 통해 문제 항목들이 얼마나 해결되었는지 확인하실 수 있습니다.');
  md.writeln('');

  for (var i = 0; i < sampleBlocks.length; i++) {
    final text = sampleBlocks[i].trim();
    if (text.isEmpty) continue;
    
    if (text.contains('기대값')) {
      final startIndex = text.indexOf('기대값');
      final endIndex = text.indexOf('*/', startIndex);
      if (endIndex != -1) {
        var expectStr = text.substring(startIndex, endIndex).trim();
        // 정상 제외
        if (expectStr.contains('- 정상') && expectStr.length < 25) {
          continue;
        }

        final testNum = i + 1;
        String parsedResult = '파싱 결과를 찾을 수 없습니다.';
        
        for (final outB in outBlocks) {
          if (outB.startsWith('\:') || outB.startsWith('\ :')) {
            parsedResult = outB.split('\n')[1].trim();
            break;
          }
        }

        md.writeln('### 📝 TEST \');
        md.writeln('**[사용자 기대값]**');
        md.writeln('`	ext');
        md.writeln(expectStr);
        md.writeln('`');
        md.writeln('**[현재 파싱 결과]**');
        md.writeln('> \');
        md.writeln('');
        md.writeln('---');
      }
    }
  }

  final reportFile = File(r'C:\Users\HYM\.gemini\antigravity\brain\97d404c9-fd70-450b-9a2e-8f8d13e1a7ac\ocr_full_verification_report.md');
  await reportFile.writeAsString(md.toString());
  print('Report generated successfully.');
}

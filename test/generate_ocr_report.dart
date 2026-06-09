import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../lib/utils/kakao_call_card_ocr.dart';
import '../lib/utils/logi_colmanner_ocr.dart';

void main() async {
  final file = File('work/ocr_log_sample.txt');
  if (!file.existsSync()) return;

  final content = await file.readAsString();
  final blocks = content.split('=========================');
  
  final md = StringBuffer();
  md.writeln('# OCR 파싱 보완 검증 보고서 (원본 대조 포함)');
  md.writeln('');
  md.writeln('아래는 ocr_log_sample.txt에 있는 원본 텍스트와, 수정된 파서를 거쳐 추출된 요금, 출발지, 도착지 결과를 함께 비교할 수 있도록 요약한 내용입니다. 불필요한 단어들(자동 설정된 주소, 10분후 자동충전 등)이 제거된 것을 볼 수 있습니다.');
  md.writeln('');

  final targetIndices = [0, 1, 2, 3, 10, 11, 25, 38]; // 1, 2, 3, 4, 11, 12, 26, 39
  
  for (final idx in targetIndices) {
    if (idx >= blocks.length) continue;
    final text = blocks[idx].trim();
    if (text.isEmpty) continue;

    final testNum = idx + 1;
    String program = '알 수 없음';
    if (text.contains('127.0.0.1:8080/logi')) program = '로지';
    else if (text.contains('127.0.0.1:8080/colmanner')) program = '콜마너';
    else if (text.contains('127.0.0.1:8080/kakao')) {
      program = KakaoCallCardOcr.detectKakaoProgram(text) ?? '카카오(일반)';
    }

    String start = '', end = '', fareStr = '';

    if (program == '로지') {
      final res = LogiColmannerOcr.parseLogi(text);
      start = res.startLocation; end = res.endLocation; fareStr = res.grossFare.toString();
    } else if (program == '콜마너') {
      final res = LogiColmannerOcr.parseColmanner(text);
      start = res.startLocation; end = res.endLocation; fareStr = res.grossFare.toString();
    } else if (program.startsWith('카카오')) {
      final res = KakaoCallCardOcr.parseScreen([], text);
      start = res.startLocation; end = res.endLocation; fareStr = res.grossFare.toString();
    }

    md.writeln('### TEST \ : \');
    md.writeln('');
    md.writeln('#### 💡 파싱 결과');
    md.writeln('- **요금**: \');
    md.writeln('- **출발지**: \');
    md.writeln('- **도착지**: \');
    md.writeln('');
    md.writeln('<details open><summary><b>📝 원본 OCR 텍스트 보기</b></summary>');
    md.writeln('');
    md.writeln('`	ext');
    final shortText = text.length > 500 ? text.substring(0, 500) + '... (중략)' : text;
    md.writeln(shortText);
    md.writeln('`');
    md.writeln('</details>');
    md.writeln('');
    md.writeln('---');
  }

  final outFile = File(r'C:\Users\HYM\.gemini\antigravity\brain\97d404c9-fd70-450b-9a2e-8f8d13e1a7ac\ocr_full_verification_report.md');
  await outFile.writeAsString(md.toString());
  print('Done');
}

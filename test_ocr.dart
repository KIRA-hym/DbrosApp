import 'dart:io';
import 'package:dbros/utils/logi_colmanner_ocr.dart';

void main() async {
  final file = File('logs/OCR 디버그 로그');
  final lines = await file.readAsLines();

  bool inRaw = false;
  bool isLogi = false;
  String currentId = '';
  List<String> rawLines = [];

  for (final line in lines) {
    if (line.startsWith('▶ [')) {
      if (inRaw && isLogi) {
        _testLogi(currentId, rawLines);
      }
      inRaw = false;
      isLogi = false;
      currentId = line;
      rawLines = [];
    } else if (line.contains('프로그램: 로지')) {
      isLogi = true;
    } else if (line.contains('─ RAW OCR 텍스트 ─')) {
      inRaw = true;
    } else if (line.startsWith('─') && inRaw) {
      if (isLogi) {
        _testLogi(currentId, rawLines);
      }
      inRaw = false;
      isLogi = false;
      rawLines = [];
    } else if (inRaw) {
      rawLines.add(line);
    }
  }
  
  if (inRaw && isLogi) {
    _testLogi(currentId, rawLines);
  }
}

void _testLogi(String id, List<String> rawLines) {
  final joined = rawLines.join('\n');
  final result = LogiColmannerOcr.parseLogi(joined, rawLines, null);
  print('========================================');
  print('\$id');
  print('요금: \${result.grossFare}원');
  print('출발: \${result.departure}');
  print('도착: \${result.destination}');
  print('경유: \${result.waypoint}');
}

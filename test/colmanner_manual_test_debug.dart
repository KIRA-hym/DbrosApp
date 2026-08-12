import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('Colmanner Missing Address Test Debug', () {
    final file = File(r'C:\dbros_app\test\colmanner_test.txt');
    final text = file.readAsStringSync();
    
    // We will parse line by line just like _parseColmannerLocations does
    final lines = text.split('\n');
    var inBlock = false;
    final buffer = <String>[];
    
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final noSpace = line.replaceAll(RegExp(r'\s+'), '');
      final n = noSpace.replaceAll(RegExp(r'[^가-힣a-zA-Z0-9]'), ''); // Approximation of _normalizeKey
      
      print('Line: $line, n: $n, inBlock: $inBlock');
      
      if (!inBlock) {
        if (n.startsWith('출발지') || n.startsWith('도착지')) {
          inBlock = true;
        } else if ((n.startsWith('지사명') || n.startsWith('고객명') || n.startsWith('위치')) && i + 1 < lines.length) {
          inBlock = true;
          continue;
        } else if (RegExp(('^' + '서울|경기|인천')).hasMatch(line)) {
          inBlock = true;
        }
      }
      
      if (!inBlock) continue;
      
      if (noSpace.contains('요금') || noSpace.contains('현금') || noSpace.contains('경로거리') || noSpace.contains('고객정보')) {
        print('BREAK at: $line');
        break;
      }
      buffer.add(line);
    }
    print('--- Buffer ---');
    print(buffer.join(' '));
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('Colmanner Missing Address Test Trace 2', () {
    final file = File(r'C:\dbros_app\test\colmanner_test.txt');
    final text = file.readAsStringSync();
    
    // Simulate what _parseColmannerLocations does
    final lines = text.split('\n');
    var inBlock = false;
    final buffer = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final noSpace = line.replaceAll(RegExp(r'\s+'), '');
      final n = noSpace.replaceAll(RegExp(r'[^가-힣a-zA-Z0-9]'), '');
      
      if (!inBlock) {
        if (n.startsWith('출발지') || n.startsWith('도착지')) {
          inBlock = true;
        } else if ((n.startsWith('지사명') || n.startsWith('고객명') || n.startsWith('위치')) && i + 1 < lines.length) {
          inBlock = true;
          continue;
        } else if (RegExp(('^' + '서울|경기|인천|강원|충북|충남|전북|전남|경북|경남|제주|부산|대구|광주|대전|울산|세종')).hasMatch(line)) {
          inBlock = true;
        }
      }
      
      if (!inBlock) continue;
      
      if (noSpace.contains('요금') || noSpace.contains('현금') || noSpace.contains('경로거리')) {
        print('BREAK at: $line');
        break;
      }
      
      if (RegExp(r'^(출도|적요|지도|고객위치|길안내|서명|갱신|닫기)$', caseSensitive: false).hasMatch(noSpace)) {
        continue;
      }
      if (n.startsWith('적요')) continue;
      if (n.startsWith('지사명') || n.startsWith('고객명')) continue;
      
      buffer.add(line);
    }
    
    final joined = buffer.join(' ');
    print('--- JOINED ---');
    print(joined);
  });
}

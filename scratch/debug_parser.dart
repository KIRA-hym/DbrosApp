import 'dart:io';
import '../lib/utils/logi_colmanner_ocr.dart';

void main() {
  String colmannerText = '''
경기 김포시 북변동 전2 북변동금딸네포차 경기 부천시원미구 도당동 장미공원 공한지 부천도당동장미공원인근
출발지
도착지
공영주차장
  ''';
  
  String logiText = '''
경기 파주시 다율동 1030번지 다율동 해오름마을13단지운정한라비발디파 크젠아파트 O 88
상세:경기 김포시 사우동 시우동 CU 김포풍년마을점
  ''';

  print('=== COLMANNER TEST ===');
  final resC = LogiColmannerOcr.parseColmanner(colmannerText);
  print('Start: ${resC.startLocation}');
  print('End: ${resC.endLocation}');

  print('\n=== LOGI TEST ===');
  final resL = LogiColmannerOcr.parseLogi(logiText);
  print('Start: ${resL.startLocation}');
  print('End: ${resL.endLocation}');
}

import 'dart:io';
import 'package:dbros_app/services/call_card_ocr_parse_service.dart';

void main() async {
  final text = await File('scratch/kakao_premium_test.txt').readAsString();
  final service = CallCardOcrParseService();
  final result = await service.parseOcrText(text, isKakaoContext: true);
  
  print('Program: ${result['program']}');
  print('Gross Fare: ${result['gross_fare']}');
  print('Net Fare: ${result['net_fare']}');
  print('Fee: ${result['fee']}');
  print('Start: ${result['start_location']}');
  print('End: ${result['end_location']}');
  print('Waypoint: ${result['waypoint']}');
}

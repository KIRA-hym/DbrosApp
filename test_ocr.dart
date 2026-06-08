import 'dart:io';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'package:dbros_app/services/remote_config_service.dart';
import 'package:dbros_app/models/call_card_ocr_result.dart';

void main() async {
  // Mock RemoteConfigService regionPattern
  // Since we are running outside Flutter, we might need to mock or just assume it works if RemoteConfigService doesn't depend on Flutter bindings.
  // Actually, RemoteConfigService is a singleton that might need initialization. Let's see if we can just test the raw static methods.
  
  // Test Case 1 (Colmanner)
  String case1 = '''
출발지
카/인천중산동 1988
출도
적요
도착지 180-27(태전동 502-48)
인천 중구 중산동
입금합계
차감합계
경기 광주시 태전동 고불로
연락처
광주태전동고불로180-27
경로거리 : 75.2km
현금 0원
(예상소요시간 : 51분)
요금 10,000원 (예상 수익금:55,336원)
상황실
후불70K]완료20분후입금> [앱접수]자동
1앱에서 전화걸기/
합계 : 70,000원
예상 후불요금 : 70,000원
합계 : 15,523원
예상 운행수수료 : 14,000원
예상 고용보험료 : 307원
상황실 1cnn8n38
15118138
예상 산재보험료 : 357원
접수시간 오전12:48
9 5l (49
고객위치 90 출도경로
운행 시작
||
킬안내
''';

  String case3 = '''
Kakao T
취소
12/12 04:31
호출완료
외발산동
수협 강서수산시장
서울 송파구 위례송파로 80
36,800
신용카드 결제요금
(1) 손님에게 직접 요금을 받지 마세요.
취소
길안내
''';

  String case5 = '''
Kakao T
취소
12/12 05:43
신사동
호출완료
아디다스오리지널스 가로수길점
경기 군포시 고산로 36
31,400
신용카드 결제요금
손님에게 직접 요금을 받지 마세요.
취소
길안내
''';

  try {
    print('Testing Case 3 (Kakao)...');
    var k3 = KakaoCallCardOcr.parseText(case3);
    print('Start: \${k3.startAddress}');
    print('End: \${k3.endAddress}');
    print('Fare: \${k3.fare}');
    print('---');

    print('Testing Case 5 (Kakao)...');
    var k5 = KakaoCallCardOcr.parseText(case5);
    print('Start: \${k5.startAddress}');
    print('End: \${k5.endAddress}');
    print('Fare: \${k5.fare}');
    print('---');

    print('Testing Case 1 (Colmanner)...');
    var lines = case1.split('\\n');
    // Since parse text methods are private or complex, we can call LogiColmannerOcr.parseText
    // But wait, parseText returns a CallCardOcrResult
    var c1 = LogiColmannerOcr.parseText(case1, isLogi: false);
    print('Start: \${c1.startAddress}');
    print('End: \${c1.endAddress}');
    print('Fare: \${c1.fare}');
    
  } catch (e) {
    print(e);
  }
}

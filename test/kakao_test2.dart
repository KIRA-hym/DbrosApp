import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test', () {
    final text = '''
이1:30 ㅠO•
배정 완료
카드 | 확정
중동
고객
시골집
인천 서구 가정동
인천가정2A-1블록행복주택아피트
운영센터
고객과 만날 장소 길찾기
고객에게 위치정보가 공유됩니다.
배정취소
Ol59
28,200
밀어서 고객에게 도착알림
고객
메뉴
10점''';
    final lines = text.split('\n');
    List<TextBlock> blocks = [];
    double y = 10;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      blocks.add(TextBlock(
        text: line.trim(),
        lines: [],
        boundingBox: Rect.fromLTWH(10, y, 100, 20),
        recognizedLanguages: [],
        cornerPoints: [],
      ));
      y += 30;
    }

    final parsed = KakaoCallCardOcr.parseScreen(blocks, text);
    
    print('Start: ${parsed.startLocation}');
    print('End: ${parsed.endLocation}');
    print('Fare: ${parsed.grossFare}');
  });
}

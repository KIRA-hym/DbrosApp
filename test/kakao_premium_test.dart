import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dbros_app/utils/kakao_call_card_ocr.dart';

void main() {
  test('Test Kakao Premium', () async {
    final text = await File('scratch/kakao_premium_test.txt').readAsString();
    
    // Simulate TextBlock list (we just provide dummy blocks based on lines)
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

    final parsed = KakaoCallCardOcr.parseScreen(blocks, text, isPremium: true);
    
    print('Start: ${parsed.startLocation}');
    print('End: ${parsed.endLocation}');
    print('Fare: ${parsed.grossFare}');
  });
}

// GEMINI_HYBRID_PARSE_BEGIN
import 'dart:io';

import 'kakao_call_card_ocr.dart';

/// 카카오 맞춤콜 — Gemini 멀티모달 파싱 (결제 힌트는 이미지 단독 추론 생략).
class KakaoCustomCallOcr {
  KakaoCustomCallOcr._();

  static const String programCustom = '카카오(맞춤)';

  static Future<KakaoScreenParsed> parseScreen(File imageFile) async {
    return KakaoCallCardOcr.parseScreen(imageFile);
  }
}
// GEMINI_HYBRID_PARSE_END

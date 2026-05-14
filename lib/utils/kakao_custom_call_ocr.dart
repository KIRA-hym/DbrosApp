// GEMINI_HYBRID_PARSE_BEGIN
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'kakao_call_card_ocr.dart';

/// 카카오 **맞춤콜** 배차 화면 — 프로그램 판별 + Gemini 파싱.
class KakaoCustomCallOcr {
  KakaoCustomCallOcr._();

  static const String programCustom = '카카오(맞춤)';

  static String _compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  static bool isCustomCallScreen(String fullText) => _compact(fullText).contains('맞춤콜');

  static Future<KakaoScreenParsed> parseScreen(List<TextBlock> blocks, String fullText) async {
    String? pay;
    if (fullText.contains('카드')) {
      pay = '카드';
    } else if (fullText.contains('현금')) {
      pay = '현금';
    }
    return KakaoCallCardOcr.parseScreen(
      blocks,
      fullText,
      programCustom,
      paymentMethodHint: pay,
    );
  }
}
// GEMINI_HYBRID_PARSE_END

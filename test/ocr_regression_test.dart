// GEMINI_HYBRID_PARSE_BEGIN
// 기존 동기 OCR 회귀 테스트는 Gemini 하이브리드 전환으로 제거됨.
// 통합 테스트는 GEMINI API 키·모킹 준비 후 이 파일에 다시 추가하면 됩니다.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'OCR regression placeholder (Gemini hybrid)',
    () => expect(true, isTrue),
    skip: 'Legacy sync parsers removed; add contract tests with mocked GeminiApiService.',
  );
}
// GEMINI_HYBRID_PARSE_END

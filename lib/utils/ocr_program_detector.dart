import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'kakao_call_card_ocr.dart';
import 'tmap_trip_detail_ocr.dart';

/// 콜카드 프로그램(콜마너·로지·티맵·카카오) 판별 공통 로직.
///
/// 자동 스샷 등록·수동 일지 작성·OCR 디버그/실험실이 모두 동일한 기준을 쓰도록 일원화.
/// 단어 1개만 우연히 포함된 일반 화면이 콜카드로 오인식되지 않도록,
/// 각 프로그램마다 **대표 키워드 + 보조 키워드 1개 이상**을 요구한다.
/// (`카카오(맞춤)`은 기능 폐지로 판별 대상에서 제외)
class OcrProgramDetector {
  OcrProgramDetector._();

  static const List<String> _colmannerHelpers = <String>[
    '출발지', '도착지', '도착시', '착지', '지사명', '고객명', '고객전화',
    '적요', '입금합계', '차감합계', '경로거리', '예상소요시간', '요금',
    '상황실', '고객위치', '출도경로', '길안내', '킬안내', '잔액',
  ];

  static const List<String> _logiReps = <String>[
    '갱신', '배차', '접수운행', '상세배차정보', '상세완료정보',
  ];

  static const List<String> _logiHelpers = <String>[
    '요금', '입금액', '적요', '출발지', '추바지', '도착지', '도착시', '도차지',
    '고객과의거리', '운행시작연기', '출발지도착연기', '이용개시', '오더번호',
    '경로', '안내', '지도', '서명', '닫기', '배차취소',
  ];

  /// 판별 결과와 판별 경로 태그를 함께 반환 (경로 태그는 디버그용).
  static ({String? program, String pathTag}) detectWithPath(
    List<TextBlock> blocks,
    String fullText,
  ) {
    if (KakaoCallCardOcr.looksLikeInternalOcrReviewDump(fullText)) {
      return (program: null, pathTag: 'internal_dump');
    }
    final normalized = fullText.replaceAll(RegExp(r'\s+'), '');

    // 1. 콜마너: 대표('출도') + 보조 1개 이상 (콜마너를 로지보다 먼저 검사)
    final hasColmannerRep = normalized.contains('출도') ||
        blocks.any((b) => b.text.replaceAll(RegExp(r'\s+'), '').contains('출도'));
    if (hasColmannerRep && _colmannerHelpers.any(normalized.contains)) {
      return (program: '콜마너', pathTag: 'colmanner');
    }

    // 2. 로지
    // (A) 하단이 잘린 로지 콜카드 대응 4중 조건
    if (normalized.contains('운행시작') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지') &&
        (normalized.contains('입금액') || normalized.contains('고객과의거리'))) {
      return (program: '로지', pathTag: 'logi_fulltext');
    }
    // (B) 대표 + 보조 1개 이상 ('운행시작'·'취소' 단독은 카카오/콜마너와 겹쳐 제외)
    final hasLogiRep = _logiReps.any(normalized.contains) ||
        blocks.any((b) => b.text.contains('갱신'));
    if (hasLogiRep && _logiHelpers.any(normalized.contains)) {
      return (program: '로지', pathTag: 'logi');
    }

    // 3. 티맵
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) {
      return (program: '티맵', pathTag: 'tmap');
    }

    // 4. 카카오
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) {
      return (
        program: KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          fullText,
          blocks,
          kakao,
        ),
        pathTag: 'kakao_fulltext',
      );
    }

    return (program: null, pathTag: 'none');
  }

  static String? detect(List<TextBlock> blocks, String fullText) =>
      detectWithPath(blocks, fullText).program;
}

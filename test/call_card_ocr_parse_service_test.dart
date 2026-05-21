import 'package:flutter_test/flutter_test.dart';

import 'package:dbros_app/services/call_card_ocr_parse_service.dart';

void main() {
  group('CallCardOcrParseService.isValidForAutoSave', () {
    test('requires program, fare, start and end', () {
      expect(
        CallCardOcrParseService.isValidForAutoSave({
          'program': '카카오(일반)',
          'gross_fare': 15000,
          'start_location': '서울역',
          'end_location': '강남역',
        }),
        isTrue,
      );
    });

    test('rejects missing start or end', () {
      const base = {
        'program': '로지',
        'gross_fare': 12000,
        'start_location': 'A',
        'end_location': 'B',
      };
      expect(
        CallCardOcrParseService.isValidForAutoSave({...base, 'start_location': ''}),
        isFalse,
      );
      expect(
        CallCardOcrParseService.isValidForAutoSave({...base, 'end_location': '  '}),
        isFalse,
      );
    });

    test('rejects zero fare and empty parse', () {
      expect(CallCardOcrParseService.isValidForAutoSave({}), isFalse);
      expect(
        CallCardOcrParseService.isValidForAutoSave({
          'program': '티맵',
          'gross_fare': 0,
          'start_location': 'A',
          'end_location': 'B',
        }),
        isFalse,
      );
    });
  });

  group('CallCardOcrParseService.isValidForScreenshotAutoSave', () {
    Map<String, dynamic> kakaoBase(String snapshot, String pathTag) => {
      'program': '카카오(일반)',
      'gross_fare': 28000,
      'start_location': 'A',
      'end_location': 'B',
      CallCardOcrParseService.internalProgramDetectPathKey: pathTag,
      CallCardOcrParseService.internalOcrSnapshotKey: snapshot,
    };

    test('blocks kakao_block_fallback detection path', () {
      expect(
        CallCardOcrParseService.isValidForScreenshotAutoSave(
          kakaoBase(
            '고객과 통화 무작위 줄만 있는 화면 28,800',
            'kakao_block_fallback',
          ),
        ),
        isFalse,
      );
    });

    test('blocks OCR debug headline dump', () {
      expect(
        CallCardOcrParseService.isValidForScreenshotAutoSave(
          kakaoBase('✅ 자동인식 성공 로그\n카카오(일반) 28800원', 'kakao_fulltext'),
        ),
        isFalse,
      );
    });

    test('allows kakao_fulltext when assignment UI present', () {
      expect(
        CallCardOcrParseService.isValidForScreenshotAutoSave(
          kakaoBase('''
배정 완료
고객과 통화
경기 성남
28,800
''',
              'kakao_fulltext'),
        ),
        isTrue,
      );
    });

    test('allows non-kakao program without extra gates', () {
      expect(
        CallCardOcrParseService.isValidForScreenshotAutoSave({
          'program': '로지',
          'gross_fare': 15000,
          'start_location': 'A',
          'end_location': 'B',
          CallCardOcrParseService.internalProgramDetectPathKey: 'logi_fulltext',
          CallCardOcrParseService.internalOcrSnapshotKey: '아무 문자열',
        }),
        isTrue,
      );
    });
  });
}

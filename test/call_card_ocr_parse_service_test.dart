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
}

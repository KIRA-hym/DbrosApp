import 'package:dbros_app/screens/ocr_error_report_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrErrorReportPage', () {
    test('메일 제목 상수가 콜카드인식오류제보로 고정되어 있다', () {
      expect(OcrErrorReportPage.reportEmailTitle, '콜카드인식오류제보');
    });

    test('buildReportEmailContent는 제보자 기본정보와 OCR 원본 텍스트를 포함한다', () {
      final content = OcrErrorReportPage.buildReportEmailContent(
        reporterEmail: 'driver@test.com',
        deviceInfo: 'Android 15 (SM-S928N)',
        appVersion: '1.1.9+110901',
        reportedAt: '2026-11-23 10:30:00',
        capturedAt: '2026-11-23T02:56:14.000',
        program: '카카오(일반)',
        grossFare: 23200,
        startLocation: '상암동 투썸플레이스',
        waypoint: '홍대입구역',
        endLocation: '서울 강북구 미아동',
        parseError: '',
        rawText: 'SKT 2:56 10개\n배정 완료\n상암동\n23,200 P',
      );

      expect(content, contains('[제보자 기본정보]'));
      expect(content, contains('이메일: driver@test.com'));
      expect(content, contains('기기정보: Android 15 (SM-S928N)'));
      expect(content, contains('앱 버전: 1.1.9+110901'));
      expect(content, contains('프로그램: 카카오(일반)'));
      expect(content, contains('총요금: 23200원'));
      expect(content, contains('출발지: 상암동 투썸플레이스'));
      expect(content, contains('경유지: 홍대입구역'));
      expect(content, contains('도착지: 서울 강북구 미아동'));
      expect(content, contains('[OCR 원본 텍스트 (RAW)]'));
      expect(content, contains('SKT 2:56 10개'));
    });

    test('parseLogEntries는 최신 역순 정렬 및 성공/실패 상태를 올바르게 매핑한다', () {
      final items = OcrErrorReportPage.parseLogEntries([
        {
          'id': 'log_1',
          'captured_at': '2026-11-22T21:18:52.000',
          'recognized': false,
          'program': '',
          'raw_text': '미인식 텍스트',
          'parsed_data': {
            'departure': '',
            'destination': '',
            'waypoints': [],
            'fee_amount': 0,
          },
        },
        {
          'id': 'log_2',
          'captured_at': '2026-11-23T02:56:14.000',
          'recognized': true,
          'program': '카카오(일반)',
          'raw_text': '배정 완료\n상암동',
          'parsed_data': {
            'departure': '상암동',
            'destination': '미아동',
            'waypoints': ['광화문'],
            'fee_amount': 23200,
          },
        },
      ]);

      expect(items.length, 2);
      // 최신 항목(log_2)이 첫 번째
      expect(items[0].id, 'log_2');
      expect(items[0].imageIndex, 1);
      expect(items[0].program, '카카오(일반)');
      expect(items[0].imageName, contains('✅ 자동인식 성공'));
      expect(items[0].grossFare, 23200);
      expect(items[0].waypoint, '광화문');
      expect(items[0].parseError, isEmpty);

      // 이전 실패 항목(log_1)이 두 번째
      expect(items[1].id, 'log_1');
      expect(items[1].imageIndex, 2);
      expect(items[1].program, '❌ 인식불가');
      expect(items[1].imageName, contains('❌ 자동인식 실패'));
      expect(items[1].parseError, '인식 실패 로그');
    });
  });
}

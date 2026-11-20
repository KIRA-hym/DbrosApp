import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/screens/call_point_map_page.dart';

void main() {
  group('CallPointMapPage.formatCallPointDateTime (YY.MM.DD HH:mm)', () {
    test('내 일지 log_drive_date + drive_time 조합을 YY.MM.DD HH:mm으로 변환', () {
      expect(
        CallPointMapPage.formatCallPointDateTime({
          'log_drive_date': '2026-11-20',
          'drive_time': '13:15',
          'created_at': '2026-11-20T14:00:00.000',
        }),
        '26.11.20 13:15',
      );
    });

    test('한 자리 시각(9:05)도 09:05로 패딩', () {
      expect(
        CallPointMapPage.formatCallPointDateTime({
          'log_drive_date': '2026-11-20',
          'drive_time': '9:05',
        }),
        '26.11.20 09:05',
      );
    });

    test('공유 콜(created_at + drive_time)에서 날짜와 운행시간 조합', () {
      expect(
        CallPointMapPage.formatCallPointDateTime({
          'created_at': '2026-11-20T14:22:10.000',
          'drive_time': '13:15',
        }),
        '26.11.20 13:15',
      );
    });

    test('drive_time이 비어 있으면 created_at의 시:분 사용', () {
      expect(
        CallPointMapPage.formatCallPointDateTime({
          'created_at': '2026-11-20T13:15:42.000',
          'drive_time': '',
        }),
        '26.11.20 13:15',
      );
    });
  });
}

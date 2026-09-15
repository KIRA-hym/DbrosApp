import 'dart:io';

void main() {
  final file = File('lib/utils/tmap_trip_detail_ocr.dart');
  var text = file.readAsStringSync();

  final targetStr = r'''    final dtMatch = RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})').firstMatch(flat);
    if (dtMatch != null) {
      final y = dtMatch.group(1)!;
      final m = dtMatch.group(2)!.padLeft(2, '0');
      final d = dtMatch.group(3)!.padLeft(2, '0');
      driveDateYmd = '\-\-\';
      driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');
    }''';

  final replaceStr = r'''    // 1. 날짜 추출 (운행일자 텍스트 무시, 1~2자리 모두 허용)
    final dateMatch = RegExp(r'(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2})').firstMatch(flat);
    if (dateMatch != null) {
      final y = dateMatch.group(1)!;
      final m = dateMatch.group(2)!.padLeft(2, '0');
      final d = dateMatch.group(3)!.padLeft(2, '0');
      driveDateYmd = '--';
    }

    // 2. 시간 추출 (00:00 패턴 스캔 후 무조건 첫 번째 매칭값 사용)
    final timeMatches = RegExp(r'(\d{2})\s*:\s*(\d{2})').allMatches(flat).toList();
    if (timeMatches.isNotEmpty) {
      driveStartTimeHm = timeMatches.first.group(0)!.replaceAll(' ', '');
    }''';

  text = text.replaceFirst(targetStr, replaceStr);
  file.writeAsStringSync(text);
}
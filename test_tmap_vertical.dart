void main() {
  String logText = """
09:55
운행번호
42443611
운행일자 2026.8.29 (토) 00:50 ~ 01:35
출발
도착
실수익
운행 상세 정보
경기 화성시 병점구 진안동 별하나라이브
경기 안산시 단원구 신길동 신길고등학교
32,000P
보험종류 TMAP 대리 보험
보험사 DB손해보험
A 사고 접수
92)
""";

  int grossFare = 0;
  String startAddress = '';
  String endAddress = '';

  // Fare Fallback
  if (grossFare == 0) {
    final fareMatch = RegExp(r'([\d,]+)\s*P').firstMatch(logText);
    if (fareMatch != null) {
      grossFare = int.tryParse(fareMatch.group(1)!.replaceAll(',', '')) ?? 0;
    }
  }

  // Vertical Address Fallback
  if (startAddress.isEmpty || endAddress.isEmpty) {
    final lines = logText.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final idx = lines.indexWhere((e) => e.replaceAll(' ', '') == '운행상세정보');
    if (idx != -1 && idx + 2 < lines.length) {
      final line1 = lines[idx + 1];
      final line2 = lines[idx + 2];
      // Basic sanity check: ensure they are not labels
      if (!line1.contains('32,000') && !line1.contains('TMAP')) {
        startAddress = line1;
      }
      if (!line2.contains('32,000') && !line2.contains('TMAP')) {
        endAddress = line2;
      }
    }
  }

  print('Fare: $grossFare');
  print('Start: $startAddress');
  print('End: $endAddress');
}

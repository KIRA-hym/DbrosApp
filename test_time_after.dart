void main() {
  String flatText = '14:43 운행 상세 정보 운행번호 42443611 운행일자 2026.8.29 (토) 00:50 ~ 01:35 출발 경기 화성시';
  
  final dateMatch = RegExp(r'(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2})').firstMatch(flatText);
  if (dateMatch != null) {
    print('Date found at: ' + dateMatch.end.toString());
    final timeMatches = RegExp(r'(\d{2})\s*:\s*(\d{2})').allMatches(flatText, dateMatch.end).toList();
    if (timeMatches.isNotEmpty) {
      print('Time found: ' + timeMatches.first.group(0)!);
    }
  }
}
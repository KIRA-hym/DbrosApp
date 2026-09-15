void main() {
  String flat = '11:52 D 운행번호 42443611 출발 운행일자 2026.8.29 (토) 00:50 ~ 01:35 도착 요기요 실수익 보험사 운행 상세 정보 경기 화성시 병점구 진안동 별하나라이브 경기 안산시 단원구 신길동 신길고등학교 32,000P 보험종류 TMAP 대리 보험 DB손해보험 A 사고 접수 EO | 81';
  final dtMatch = RegExp(r'운행일자\s*(\d{4})[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~').firstMatch(flat);
  if (dtMatch != null) {
      final y = dtMatch.group(1)!;
      final m = dtMatch.group(2)!.padLeft(2, '0');
      final d = dtMatch.group(3)!.padLeft(2, '0');
      print('Date: $y-$m-$d, Time: ${dtMatch.group(4)}');
  } else {
      print('Failed date regex');
  }
}

void main() {
  String normalized = '''
운행 상세 정보
운행번호
42443611
운행일자 2026.8.29 (토) 00:50 ~ 01:35
출발
경기 화성시 병점구 진안동 별하나라이브
도착
경기 안산시 단원구 신길동 신길고등학교
실수익
32,000P
보험종류 TMAP 대리 보험
보험사 DB손해보험
사고 접수
''';

  var startAddress = '';
  var endAddress = '';
  
  final flat = normalized.replaceAll(RegExp(r'\s+'), ' ');
  final addrRegex = RegExp(r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)\s+[가-힣]+(?:시|군|구)\s+[^도착실수익\n]*');
  final matches = addrRegex.allMatches(flat).toList();
  
  if (matches.isNotEmpty) {
    if (startAddress.isEmpty) startAddress = matches.first.group(0)!.trim();
    if (endAddress.isEmpty) endAddress = matches.last.group(0)!.trim();
  }

  print('START: ' + startAddress);
  print('END: ' + endAddress);
}
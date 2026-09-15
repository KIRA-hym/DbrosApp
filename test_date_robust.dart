void main() {
  // 1. 극단적인 악조건 시뮬레이션 (운행일자와 날짜 사이에 워터마크가 떡칠된 상황)
  String flatText = '운행 상세 정보 운행번호 42443611 운행일자 SM운영팀 / 명훈이 (700004009) 2026.8.29 (토) 00:50 ~ 01:35 출발 경기 화성시 병점구 진안동 별하나라이브 도착 경기 안산시 단원구 신길동 신길고등학교 실수익 32,000P';

  var driveDateYmd = '';
  var driveStartTimeHm = '';

  // 2. 날짜 찾기 (운행일자 글자 무시, 연.월.일 패턴 자체를 스캔)
  // 1~2자리 수 모두 매칭: \d{1,2}
  final dateRegex = RegExp(r'(\d{4})\s*[.\-년]\s*(\d{1,2})\s*[.\-월]\s*(\d{1,2})');
  final dateMatch = dateRegex.firstMatch(flatText);
  
  if (dateMatch != null) {
    final y = dateMatch.group(1)!;
    final m = dateMatch.group(2)!.padLeft(2, '0');
    final d = dateMatch.group(3)!.padLeft(2, '0');
    driveDateYmd = '$y-$m-$d';
  }

  // 3. 시간 찾기 (00:00 패턴 스캔)
  final timeRegex = RegExp(r'(\d{2})\s*:\s*(\d{2})');
  final timeMatches = timeRegex.allMatches(flatText).toList();
  
  if (timeMatches.isNotEmpty) {
    // 첫 번째 시간만 무조건 추출 (시작 시간)
    driveStartTimeHm = timeMatches.first.group(0)!.replaceAll(' ', '');
  }

  print('=== 추출 테스트 결과 ===');
  print('운행일자 : $driveDateYmd');
  print('운행시간 : $driveStartTimeHm');
  if (timeMatches.length > 1) {
    print('(참고) 무시된 종료시간 : ' + timeMatches[1].group(0)!.replaceAll(' ', ''));
  }
  print('========================');
}
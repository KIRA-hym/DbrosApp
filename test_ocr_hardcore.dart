void main() {
  // 시뮬레이션: 기기에서 발생한 '악조건' 상황을 재현한 텍스트
  // 1. 도착지와 요금, 보험 등이 줄바꿈 없이 한 줄로 뭉쳐있음
  // 2. 시간 뒤의 기호가 이상한 기호(～)로 들어옴
  String fullText = '''
11:52 D
운행번호
42443611
출발
운행일자 2026.8.29 (토) 00:50 ～ 01:35
도착
요기요
실수익
보험사
운행 상세 정보
경기 화성시 병점구 진안동 별하나라이브
경기 안산시 단원구 신길동 신길고등학교 32,000P 보험종류 TMAP 대리 보험 DB손해보험 A 사고 접수
EO | 81
''';

  String normalized = fullText.replaceAll('\r', '\n');
  var grossFare = 0;
  var startAddress = '';
  var endAddress = '';

  // 1. 기존 가로형 파싱 (가짜 주소 필터링)
  var addrStart = '';
  var addrEnd = '';
  try {
    final iStart = normalized.indexOf('출발');
    final iEnd = normalized.indexOf('도착', iStart != -1 ? iStart : 0);
    final iFare = normalized.indexOf('실수익', iEnd != -1 ? iEnd : 0);
    if (iStart != -1 && iEnd != -1) addrStart = normalized.substring(iStart + 2, iEnd).trim();
    if (iEnd != -1 && iFare != -1) addrEnd = normalized.substring(iEnd + 2, iFare).trim();
  } catch (_) {}
  
  startAddress = addrStart;
  endAddress = addrEnd;

  if (startAddress.contains('운행일자') || startAddress.contains('운행번호') || startAddress.contains('요기요')) startAddress = '';
  if (endAddress.contains('운행일자') || endAddress.contains('운행번호') || endAddress.contains('요기요')) endAddress = '';

  // 2. 세로형 파싱 (안전망)
  if (startAddress.isEmpty || endAddress.isEmpty) {
    final lines = normalized.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final infoIdx = lines.indexWhere((e) => e.replaceAll(RegExp(r'\s+'), '') == '운행상세정보');
    if (infoIdx != -1 && infoIdx + 2 < lines.length) {
      final s = lines[infoIdx + 1];
      final e = lines[infoIdx + 2];
      if (startAddress.isEmpty && s.length > 3) startAddress = s;
      if (endAddress.isEmpty && e.length > 3) endAddress = e;
    }
  }

  // ★ 3. 추가된 안전장치: 뭉친 주소에서 쓰레기 텍스트 강제 자르기 (Cut-off)
  String cleanAddr(String a) {
    var res = a;
    // 요금(예: 32,000P) 패턴이 보이면 그 앞까지만 자름
    final fareMatch = RegExp(r'\d{1,3}(,\d{3})*\s*[P원]').firstMatch(res);
    if (fareMatch != null) res = res.substring(0, fareMatch.start);
    // '보험' 단어가 보이면 그 앞까지만 자름
    final insIdx = res.indexOf('보험');
    if (insIdx != -1) res = res.substring(0, insIdx);
    return res.trim();
  }
  
  startAddress = cleanAddr(startAddress);
  endAddress = cleanAddr(endAddress);

  // 4. 요금 추출
  final fareMatch = RegExp(r'([\d,]+)\s*P').firstMatch(normalized.replaceAll(RegExp(r'\s+'), ' '));
  if (fareMatch != null) {
    grossFare = int.tryParse(fareMatch.group(1)!.replaceAll(',', '')) ?? 0;
  }

  // ★ 5. 수정된 날짜 추출 (물결표 조건 삭제)
  var driveDateYmd = '';
  var driveStartTimeHm = '';
  final flat = normalized.replaceAll(RegExp(r'\s+'), ' ');
  // 기존: 마지막에 \s*~ 가 있었으나 삭제함
  final dtMatch = RegExp(r'운행일자\s*(\d{4})\s*[.\-년]\s*(\d{1,2})\s*[.\-월]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})').firstMatch(flat);
  if (dtMatch != null) {
    final y = dtMatch.group(1)!;
    final m = dtMatch.group(2)!.padLeft(2, '0');
    final d = dtMatch.group(3)!.padLeft(2, '0');
    driveDateYmd = '$y-$m-$d';
    driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');
  }

  print('=== 악조건 OCR 테스트 결과 ===');
  print('출발지 : $startAddress');
  print('도착지 : $endAddress');
  print('요금   : $grossFare');
  print('날짜   : $driveDateYmd');
  print('시간   : $driveStartTimeHm');
}
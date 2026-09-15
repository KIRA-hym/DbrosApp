void main() {
  String fullText = '''
11:52 D
운행번호
42443611
출발
운행일자 2026.8.29 (토) 00:50 ~ 01:35
도착
요기요
실수익
보험사
운행 상세 정보
경기 화성시 병점구 진안동 별하나라이브
경기 안산시 단원구 신길동 신길고등학교
32,000P
보험종류 TMAP 대리 보험
DB손해보험
A 사고 접수
EO | 81
''';

  String normalized = fullText.replaceAll('\r', '\n');
  var grossFare = 0;
  var startAddress = '';
  var endAddress = '';
  var waypoint = '';

  int parseGrossFare(String source) {
    final match = RegExp(r'실수익\s*[:\s]*([\d,]+)\s*[P원]').firstMatch(source);
    if (match != null) {
      return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
    }
    return 0;
  }

  (String, String) parseAddresses(String source) {
    var s = '';
    var e = '';
    try {
      final iStart = source.indexOf('출발');
      final iEnd = source.indexOf('도착', iStart != -1 ? iStart : 0);
      final iFare = source.indexOf('실수익', iEnd != -1 ? iEnd : 0);
      if (iStart != -1 && iEnd != -1) {
        s = source.substring(iStart + 2, iEnd).trim();
      }
      if (iEnd != -1 && iFare != -1) {
        e = source.substring(iEnd + 2, iFare).trim();
      }
    } catch (_) {}
    return (s, e);
  }

  // Horizontal parse
  grossFare = parseGrossFare(normalized);
  final addr = parseAddresses(normalized);
  if (startAddress.isEmpty && addr.$1.isNotEmpty) startAddress = addr.$1;
  if (endAddress.isEmpty && addr.$2.isNotEmpty) endAddress = addr.$2;

  // Clear false positives
  if (startAddress.contains('운행일자') || startAddress.contains('운행번호') || startAddress.contains('요기요')) startAddress = '';
  if (endAddress.contains('운행일자') || endAddress.contains('운행번호') || endAddress.contains('요기요')) endAddress = '';

  // Vertical parse fallback
  if (startAddress.isEmpty || endAddress.isEmpty) {
    final lines = normalized.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final infoIdx = lines.indexWhere((e) => e.replaceAll(RegExp(r'\s+'), '') == '운행상세정보');
    if (infoIdx != -1 && infoIdx + 2 < lines.length) {
      final s = lines[infoIdx + 1];
      final e = lines[infoIdx + 2];
      if (startAddress.isEmpty && s.length > 3 && !s.contains(RegExp(r'[\d,]+\s*[P원]$')) && !s.contains('운행') && !s.contains('보험')) {
        startAddress = s;
      }
      if (endAddress.isEmpty && e.length > 3 && !e.contains(RegExp(r'[\d,]+\s*[P원]$')) && !e.contains('운행') && !e.contains('보험')) {
        endAddress = e;
      }
    }
  }

  // Fare fallback
  if (grossFare == 0) {
    final fareMatch = RegExp(r'([\d,]+)\s*P').firstMatch(normalized.replaceAll(RegExp(r'\s+'), ' '));
    if (fareMatch != null) {
      grossFare = int.tryParse(fareMatch.group(1)!.replaceAll(',', '')) ?? 0;
    }
  }

  var driveDateYmd = '';
  var driveStartTimeHm = '';
  final flat = normalized.replaceAll(RegExp(r'\s+'), ' ');
  final dtMatch = RegExp(r'운행일자\s*(\d{4})\s*[.\-년]\s*(\d{1,2})\s*[.\-월]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~').firstMatch(flat);
  if (dtMatch != null) {
    final y = dtMatch.group(1)!;
    final m = dtMatch.group(2)!.padLeft(2, '0');
    final d = dtMatch.group(3)!.padLeft(2, '0');
    driveDateYmd = '$y-$m-$d';
    driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');
  }

  print('=== TEST RESULTS ===');
  print('Start Address : $startAddress');
  print('End Address   : $endAddress');
  print('Gross Fare    : $grossFare');
  print('Drive Date    : $driveDateYmd');
  print('Drive Time    : $driveStartTimeHm');
}
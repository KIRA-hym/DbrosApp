/// 로지 OCR 숫자 토큰의 **원→1/2** 맨끝 오인식·`I0000`→7만 등을 보정한다.
int? normalizeLogiFareDigitToken(String digits) {
  var val = digits.trim();
  if (val.isEmpty) return null;

  // 요금·입금액 줄: I/l + 0000 → 70000
  if (RegExp(r'^[Il]0{4}$', caseSensitive: false).hasMatch(val)) {
    return 70000;
  }

  // 140002 / 250001 — 끝 1·2는 「원」 오인식
  if (val.length == 6 && (val.endsWith('1') || val.endsWith('2'))) {
    val = val.substring(0, 5);
  } else if (val.length == 5 && (val.endsWith('1') || val.endsWith('2'))) {
    final raw = int.tryParse(val);
    if (raw != null && raw % 100 != 0) {
      val = '${val.substring(0, 4)}0'; // 14002 → 14000
    }
  }

  final n = int.tryParse(val);
  if (n == null || n < 1000 || n > 999999) return null;
  if (n % 100 != 0) return null;
  return n;
}

/// 로지 콜카드 OCR에서 요금만 안정적으로 추출합니다.
int? parseLogiFareFromOcrText(String raw) {
  if (raw.trim().isEmpty) return null;

  // [보완] 명백한 전화번호, 시간, 콜센터 메모 등 요금이 아닌 패턴 필터링
  // 역할별로 정규식을 쪼개어 가독성 및 유지보수성을 높입니다.
  
  // 1. 대괄호로 둘러싸인 콜센터 메모 패턴 (예: [1517-3500 151-3500 00:40])
  final memoBracketPattern = RegExp(r'^\s*\[.*\]\s*$');
  
  // 2. 전화번호 패턴 (예: 1517-3500, 0508-5017-1112)
  final phonePattern1 = RegExp(r'\d{2,4}-\d{3,4}-\d{4}');
  final phonePattern2 = RegExp(r'\d{4}-\d{4}');
  
  // 3. 시간 패턴 (예: 00:40, 14:30) - 요금 문자열이 없을 때만 차단
  final timePattern = RegExp(r'\d{1,2}:\d{2}');

  if (memoBracketPattern.hasMatch(raw)) return null;
  if (phonePattern1.hasMatch(raw)) return null;
  if (phonePattern2.hasMatch(raw)) return null;
  if (timePattern.hasMatch(raw) && !raw.contains('요금')) return null;

  String prepare(String r) {
    var s = r.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    
    // [보완] 숫자에 붙은 '2!' 나 '1!' 등은 '원'의 전형적인 오인식이므로 선제 제거
    s = s.replaceAll(RegExp(r'[12]!+$'), '');
    
    s = s.replaceAll(RegExp(r'원|₩|P'), '');
    s = s.replaceAll(RegExp(r'[!]+'), '');
    // I0000 / l0000 — l→1 치환 전에 7만원 패턴 인식
    if (RegExp(r'^[Il]0{4}$', caseSensitive: false).hasMatch(s)) {
      return '70000';
    }
    // OCR 오인식 (한글 일괄 제거 전에 혼입 문자만 보정)
    s = s.replaceAll('그', '7').replaceAll('기', '7').replaceAll('o', '0').replaceAll('O', '0');
    s = s.replaceAll('l', '1').replaceAll('L', '1').replaceAll('I', '1').replaceAll('i', '1');
    // 숫자 사이 s/S→5, z/Z→2 (예: 35s000 → 35000)
    s = s.replaceAllMapped(RegExp(r'(?<=[\d,.])[sS](?=[\d,.])'), (_) => '5');
    s = s.replaceAllMapped(RegExp(r'(?<=[\d,.])[zZ](?=[\d,.])'), (_) => '2');
    s = s.replaceAll(RegExp(r'[\uAC00-\uD7A3]'), '');
    return s;
  }

  int? bestFrom(String s) {
    if (s == '70000') return 70000;

    final matches = RegExp(r'\d{4,6}').allMatches(s);
    if (matches.isEmpty) return null;
    final candidates = matches.map((m) => m.group(0)!).toList()
      ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));

    for (final token in candidates) {
      final n = normalizeLogiFareDigitToken(token);
      if (n != null) return n;
    }
    return null;
  }

  return bestFrom(prepare(raw));
}

/// 전체 OCR 텍스트에서 **총요금(요금 라벨 기준)** 만 추출한다.
/// [colmanner]이 true이면 콜마너용 패턴을 우선한다.
int? parseGrossFareRegexFromFullText(String fullText, {bool colmanner = false}) {
  if (fullText.trim().isEmpty) return null;
  // 입금액, 차감 등 수수료 관련 줄을 원천 제거하여 오인식 방지
  final validLines = fullText.split(RegExp(r'[\r\n]+')).where((l) {
    final t = l.replaceAll(' ', '');
    return !t.contains('입금') && !t.contains('차감') && !t.contains('수익') && !t.contains('잔액');
  }).join(' ');

  final flat = validLines.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (colmanner) {
    // [이슈A 보완] '합계 : N원' 또는 '예상 후불요금 : N원' 형태 → 실제 운행 요금
    // '요금 N원'보다 더 아래에 적히는 콜마너의 후불 합산 명세를 우선 추출
    final hapgyeMatch = RegExp(r'(?:후불요금|합계)\s*[:：]\s*([\d,]+)원').firstMatch(flat);
    if (hapgyeMatch != null) {
      final v = int.tryParse(hapgyeMatch.group(1)!.replaceAll(',', ''));
      if (v != null && v >= 10000 && v <= 999999) return v;
    }

    final m = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기sSzZ]+)(?:원|\s)*(?=\()').firstMatch(flat);
    if (m != null) return parseLogiFareFromOcrText(m.group(1)!);

    final m2 = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기sSzZ]+)').firstMatch(flat);
    if (m2 != null) return parseLogiFareFromOcrText(m2.group(1)!);
  } else {
    final m = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기!sSzZ]+)').firstMatch(flat);
    if (m != null) return parseLogiFareFromOcrText(m.group(1)!);
  }
  return null;
}

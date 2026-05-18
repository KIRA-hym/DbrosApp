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

  String prepare(String r) {
    var s = r.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
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

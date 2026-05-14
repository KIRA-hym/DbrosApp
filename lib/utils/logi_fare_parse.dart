/// 로지 콜카드 OCR에서 요금만 안정적으로 추출합니다.
/// `replaceAll('l','1')`를 먼저 하면 '원' 오인식 `l`이 붙어 20000 → 200001이 되는 문제를 피합니다.
int? parseLogiFareFromOcrText(String raw) {
  if (raw.trim().isEmpty) return null;

  String prepare(String r) {
    var s = r.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    s = s.replaceAll(RegExp(r'원|₩'), '');
    s = s.replaceAll(RegExp(r'[!]+'), '');
    s = s.replaceAll(RegExp(r'[\uAC00-\uD7A3]'), '');
    s = s.replaceAll('그', '7').replaceAll('o', '0').replaceAll('O', '0');
    return s;
  }

  int? bestFrom(String s) {
    final matches = RegExp(r'\d{4,6}').allMatches(s);
    if (matches.isEmpty) return null;
    final candidates = matches.map((m) => m.group(0)!).toList()
      ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
    var val = candidates.first;
    if (val.length == 6 && val.endsWith('2')) {
      val = val.substring(0, 5);
    }
    final n = int.tryParse(val);
    if (n == null || n < 100 || n > 999_999) return null;
    return n;
  }

  final String prepared = prepare(raw);
  final int? withoutL = bestFrom(prepared);
  if (withoutL != null) return withoutL;

  final String withL = prepared.replaceAll('l', '1').replaceAll('L', '1');
  return bestFrom(withL);
}

int? _fareDigitGroupToInt(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s,]'), '');
  s = s.replaceAll('.', '');
  s = s.replaceAll(RegExp(r'[!]+'), '');
  s = s.replaceAll('l', '1').replaceAll('L', '1').replaceAll('I', '1').replaceAll('i', '1');
  s = s.replaceAll('o', '0').replaceAll('O', '0');
  return int.tryParse(s);
}

/// 전체 OCR 텍스트에서 **총요금(요금 라벨 기준)** 만 추출한다.
/// [colmanner]이 true이면 콜마너용 패턴(無「원」·예상 수익 앵커)을 우선한다.
/// 실패 시 null → 줄 단위 폴백(엄격한 독립 숫자만)으로 넘긴다.
int? parseGrossFareRegexFromFullText(String fullText, {bool colmanner = false}) {
  if (fullText.trim().isEmpty) return null;
  final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  int? tryGroup1(String g) {
    final v = _fareDigitGroupToInt(g);
    if (v != null && v >= 1000 && v <= 999_999) return v;
    return null;
  }

  if (colmanner) {
    // 괄호 직전 숫자만 — "(예상 수익금:…)" 등 괄호 안 수익금 배제
    final beforeParen = RegExp(
      r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.]+)(?:원|\s)*(?=\()',
      caseSensitive: false,
    );
    final mParen = beforeParen.firstMatch(flat);
    if (mParen != null) {
      final v = tryGroup1(mParen.group(1)!);
      if (v != null) return v;
    }
    for (final m in RegExp(
      r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.]+)(?:원|\s)*(?:\(|\s*예상)',
      caseSensitive: false,
    ).allMatches(flat)) {
      final v = tryGroup1(m.group(1)!);
      if (v != null) return v;
    }
  } else {
    for (final m in RegExp(
      r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.!]+?)(?=\s*(?:원|입금|고객|오더|차량|$|!))',
      caseSensitive: false,
    ).allMatches(flat)) {
      final v = tryGroup1(m.group(1)!);
      if (v != null) return v;
    }
  }

  for (final m in RegExp(
    r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.]+?)\s*원\s*\(',
    caseSensitive: false,
  ).allMatches(flat)) {
    final v = tryGroup1(m.group(1)!);
    if (v != null) return v;
  }

  for (final m in RegExp(
    r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.]+?)\s*원',
    caseSensitive: false,
  ).allMatches(flat)) {
    final tail = flat.substring(m.end).trimLeft();
    if (tail.startsWith('(') && RegExp(r'^\(\s*예상', caseSensitive: false).hasMatch(tail)) {
      continue;
    }
    final v = tryGroup1(m.group(1)!);
    if (v != null) return v;
  }

  return null;
}

/// 로지 콜카드 OCR에서 요금만 안정적으로 추출합니다.
int? parseLogiFareFromOcrText(String raw) {
  if (raw.trim().isEmpty) return null;

  String prepare(String r) {
    var s = r.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    s = s.replaceAll(RegExp(r'원|₩|P|!'), '');
    // OCR 오인식 보정 (한글 일괄 제거 전)
    s = s.replaceAll('그', '7').replaceAll('기', '7').replaceAll('o', '0').replaceAll('O', '0');
    s = s.replaceAll('l', '1').replaceAll('L', '1').replaceAll('I', '1').replaceAll('i', '1');
    s = s.replaceAll(RegExp(r'[\uAC00-\uD7A3]'), '');
    return s;
  }

  int? bestFrom(String s) {
    final matches = RegExp(r'\d{4,6}').allMatches(s);
    if (matches.isEmpty) return null;
    final candidates = matches.map((m) => m.group(0)!).toList()
      ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
    
    var val = candidates.first;
    // 140002 오인식 방어 (6자리이면서 끝이 1이나 2로 끝나면 잘라냄)
    if (val.length == 6 && (val.endsWith('1') || val.endsWith('2'))) {
      val = val.substring(0, 5);
    }
    
    final n = int.tryParse(val);
    if (n == null || n < 1000 || n > 999999) return null;
    return n;
  }

  return bestFrom(prepare(raw));
}

int? _fareDigitGroupToInt(String raw) {
  return parseLogiFareFromOcrText(raw);
}

/// 전체 OCR 텍스트에서 **총요금(요금 라벨 기준)** 만 추출한다.
int? parseGrossFareRegexFromFullText(String fullText, {bool colmanner = false}) {
  if (fullText.trim().isEmpty) return null;

  // [핵심 방어] 입금·차감·잔액 줄 제외. '수익'만 있는 줄은 제외하되, 같은 줄에 '요금'이 있으면 유지(예상 수익금 괄호 등).
  final validLines = fullText.split(RegExp(r'[\r\n]+')).where((l) {
    final t = l.replaceAll(' ', '');
    if (t.contains('입금') || t.contains('차감') || t.contains('잔액')) return false;
    if (t.contains('수익') && !t.contains('요금')) return false;
    return true;
  }).join(' ');

  final flat = validLines.replaceAll(RegExp(r'\s+'), ' ').trim();

  int? tryGroup1(String g) {
    final v = _fareDigitGroupToInt(g);
    if (v != null && v >= 1000 && v <= 999999) return v;
    return null;
  }

  if (colmanner) {
    final beforeParen = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기]+)(?:원|\s)*(?=\()', caseSensitive: false);
    final mParen = beforeParen.firstMatch(flat);
    if (mParen != null) {
      final v = tryGroup1(mParen.group(1)!);
      if (v != null) return v;
    }
    final m2 = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기]+)', caseSensitive: false).firstMatch(flat);
    if (m2 != null) {
      final v = tryGroup1(m2.group(1)!);
      if (v != null) return v;
    }
  } else {
    final m = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기!]+)', caseSensitive: false).firstMatch(flat);
    if (m != null) {
      final v = tryGroup1(m.group(1)!);
      if (v != null) return v;
    }
  }

  return null;
}

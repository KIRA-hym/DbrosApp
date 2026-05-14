/// 로지 콜카드 OCR에서 요금만 안정적으로 추출합니다.
int? parseLogiFareFromOcrText(String raw) {
  if (raw.trim().isEmpty) return null;

  String prepare(String r) {
    var s = r.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    s = s.replaceAll(RegExp(r'원|₩|P'), '');
    s = s.replaceAll(RegExp(r'[!]+'), '');
    // OCR 오인식 (한글 일괄 제거 전에 혼입 문자만 보정)
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
    // 140002 -> 14000 처리 (끝에 붙은 오인식 숫자 제거)
    if (val.length == 6 && (val.endsWith('1') || val.endsWith('2'))) {
      val = val.substring(0, 5);
    }
    final n = int.tryParse(val);
    if (n == null || n < 1000 || n > 999999) return null;
    return n;
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
    final m = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기]+)(?:원|\s)*(?=\()').firstMatch(flat);
    if (m != null) return parseLogiFareFromOcrText(m.group(1)!);

    final m2 = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기]+)').firstMatch(flat);
    if (m2 != null) return parseLogiFareFromOcrText(m2.group(1)!);
  } else {
    final m = RegExp(r'(?:요\s*금|요금)\s*[:：]?\s*([\d\s,oOlLIi\.그기!]+)').firstMatch(flat);
    if (m != null) return parseLogiFareFromOcrText(m.group(1)!);
  }
  return null;
}

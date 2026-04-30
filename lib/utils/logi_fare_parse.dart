/// 로지 콜카드 OCR에서 요금만 안정적으로 추출합니다.
/// `replaceAll('l','1')`를 먼저 하면 '원' 오인식 `l`이 붙어 20000 → 200001이 되는 문제를 피합니다.
int? parseLogiFareFromOcrText(String raw) {
  if (raw.trim().isEmpty) return null;

  String prepare(String r) {
    var s = r.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    s = s.replaceAll(RegExp(r'원|₩'), '');
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

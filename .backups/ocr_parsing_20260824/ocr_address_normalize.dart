/// 콜카드 주소 OCR 공통 전처리 — UI 노이즈 제거·지하/층수 오인식 보정.

/// 앱 UI 문구·OCR 뭉개짐 토큰을 공백으로 치환한다.
String stripCallCardUiNoiseTokens(String s) {
  var res = s;
  const compact = [
    '상황실연락처',
    '밀어서고객에게',
    '취소불가',
    '잔여시간',
    '고객메모',
    '맞춤콜',
    '출발지에도착',
  ];
  for (final p in compact) {
    res = res.replaceAll(p, ' ');
  }
  res = res.replaceAll(RegExp(r'상황실\s*연락처'), ' ');
  res = res.replaceAll(RegExp(r'밀어서\s*고객에게'), ' ');
  res = res.replaceAll(RegExp(r'잔여\s*시간'), ' ');
  res = res.replaceAll(RegExp(r'고객\s*메모'), ' ');
  res = res.replaceAll(RegExp(r'출발지에\s*도착'), ' ');
  return res.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 지하·층수 OCR 오인식 보정 (지핟→지하, 1총→1층, B!→B1 등).
String correctFloorBasementOcrMisread(String s) {
  var res = s;
  res = res.replaceAll(RegExp(r'지핟|지합'), '지하');
  res = res.replaceAllMapped(
    RegExp(r'([0-9B])총', caseSensitive: false),
    (m) => '${m.group(1)}층',
  );
  res = res.replaceAll(RegExp(r'B!|B\|'), 'B1');
  return res.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [stripCallCardUiNoiseTokens] + [correctFloorBasementOcrMisread].
String normalizeCallCardAddressOcr(String s) {
  if (s.trim().isEmpty) return '';
  return correctFloorBasementOcrMisread(stripCallCardUiNoiseTokens(s));
}

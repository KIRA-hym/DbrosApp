/// OCR·콜앱 등 비정규 문자열을 지오코딩·네이버 길찾기에 넘기기 좋게 다듬습니다.
String normalizeAddressForGeocode(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = s.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (lines.length > 1) {
    String? best;
    int bestScore = -1;
    for (final line in lines) {
      final score = _addressLineScore(line);
      if (score > bestScore) {
        bestScore = score;
        best = line;
      }
    }
    if (best != null && bestScore >= 2) {
      s = best;
    } else {
      s = lines.join(' ');
    }
  }

  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  s = s.replaceFirst(RegExp(r'^상세\s*[:：]\s*', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^법\s*[:：]?\s*', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^출발지\s*[:：]?\s*', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^도착지\s*[:：]?\s*', caseSensitive: false), '');

  const noisePrefixes = <String>[
    '(제휴)',
    '즉후)',
    '정장)',
    '후불)',
    '@스타',
    '킥보드x',
    '킥보드X',
  ];
  for (final p in noisePrefixes) {
    s = s.replaceAll(p, ' ');
  }

  s = s.replaceAll(RegExp(r'[/@\\|]+'), ' ');
  s = s.replaceAll(RegExp(r'[)\]}]+'), ' ');
  s = s.replaceAll(RegExp(r'[(]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (s.length > 120) {
    s = s.substring(0, 120).trim();
  }
  return s;
}

int _addressLineScore(String line) {
  int score = 0;
  if (RegExp(r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)').hasMatch(line)) {
    score += 3;
  }
  if (RegExp(r'(시|군|구)\s').hasMatch(line)) score += 2;
  if (RegExp(r'\d').hasMatch(line)) score += 2;
  if (RegExp(r'(동|읍|면|리|로|길)\s*\d').hasMatch(line)) score += 2;
  return score;
}

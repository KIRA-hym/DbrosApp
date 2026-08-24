/// 콜카드 주소 OCR 공통 전처리 - UI 노이즈 제거·지하 층수 오인식 보정.

/// 대리 기사용 메모 등 주소에 포함될 수 없는 단어들을 완전히 제거합니다.
String removeDriverMemos(String s) {
  var res = s;
  const eraseWords = [
    '킥보드', '휠', '즉후', '카드', 'x)', 'X)', ')'
  ];
  for (final w in eraseWords) {
    res = res.replaceAll(w, ' ');
  }
  res = res.replaceAll(RegExp(r',\s*'), ' ');
  return res;
}

/// 주소 뒤에 꼬리표처럼 붙어오는 UI 텍스트, 경유지 기호 등을 만나면 그 뒤를 전부 잘라냅니다.
String truncateLocationNoise(String s) {
  var res = s;
  final truncateMarkers = [
    '상세 정보',
    '일반 항상',
    '일반 고객',
    r'\$',
    '@',
    '기사메모',
    '기사',
    '메모',
    '상세:',
    '>',
    r'\*'
  ];
  
  for (final marker in truncateMarkers) {
    final match = RegExp(marker).firstMatch(res);
    if (match != null) {
      res = res.substring(0, match.start);
    }
  }
  return res;
}

/// 앱 UI 문구·OCR 뭉개진 토큰을 공백으로 치환한다.
String stripCallCardUiNoiseTokens(String s) {
  var res = s;
  const compact = [
    '상황실연락처',
    '밑에서고객에게',
    '취소불가',
    '대여시간',
    '고객메모',
    '맞춤콜',
    '출발지도착',
  ];
  for (final p in compact) {
    res = res.replaceAll(p, ' ');
  }
  res = res.replaceAll(RegExp(r'상황실\s*연락처'), ' ');
  res = res.replaceAll(RegExp(r'밑에서\s*고객에게'), ' ');
  res = res.replaceAll(RegExp(r'대여\s*시간'), ' ');
  res = res.replaceAll(RegExp(r'고객\s*메모'), ' ');
  res = res.replaceAll(RegExp(r'출발지\s*도착'), ' ');
  return res.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 지하·층수 OCR 오인식 보정 (지下→지하, 1총→1층, B!→B1 등).
String correctFloorBasementOcrMisread(String s) {
  var res = s;
  res = res.replaceAll(RegExp(r'지下|지핟'), '지하');
  res = res.replaceAllMapped(
    RegExp(r'([0-9B])총', caseSensitive: false),
    (m) => '${m.group(1)}층',
  );
  res = res.replaceAll(RegExp(r'B!|B\|'), 'B1');
  return res.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [stripCallCardUiNoiseTokens] + [correctFloorBasementOcrMisread] + 잡음 꼬리자르기.
String normalizeCallCardAddressOcr(String s) {
  if (s.trim().isEmpty) return '';
  var processed = s;
  
  processed = stripCallCardUiNoiseTokens(processed);
  processed = removeDriverMemos(processed);
  processed = truncateLocationNoise(processed);
  processed = correctFloorBasementOcrMisread(processed);
  
  final words = processed.split(' ').where((w) => w.isNotEmpty).toList();
  final resultWords = <String>[];
  for (final w in words) {
    bool isDuplicate = false;
    for (final existing in resultWords) {
      if (existing == w || existing.contains(w)) {
        isDuplicate = true;
        break;
      } else if (w.contains(existing)) {
        isDuplicate = true;
        resultWords[resultWords.indexOf(existing)] = w;
        break;
      }
    }
    if (!isDuplicate) {
      resultWords.add(w);
    }
  }
  
  return resultWords.join(' ').trim();
}

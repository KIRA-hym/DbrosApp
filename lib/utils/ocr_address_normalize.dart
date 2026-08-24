/// 콜카드 주소 OCR 공통 전처리 - UI 노이즈 제거·지하 층수 오인식 보정.

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

String normalizeCallCardAddressOcr(String s) {
  if (s.trim().isEmpty) return '';
  var processed = s;
  
  processed = stripCallCardUiNoiseTokens(processed);
  processed = removeDriverMemos(processed);
  processed = truncateLocationNoise(processed);
  processed = correctFloorBasementOcrMisread(processed);
  
  // 중복 단어 제거 로직: 
  // '내손동'을 '의왕내손동물...'이 덮어쓰는 오류를 막기 위해
  // 오직 "완전히 동일한 단어"가 반복되거나, 
  // "두산위브트레지움아파트" 뒤에 "금곡동두산위브트레지움" 처럼 의미 없는 반복일 때만 단순 필터링
  final words = processed.split(' ').where((w) => w.isNotEmpty).toList();
  final resultWords = <String>[];
  for (final w in words) {
    if (w.length <= 1) {
      // 1글자짜리 찌꺼기(예: '금', '곡')는 앞뒤 문맥에 합쳐지지 않으면 버림 처리하거나 살림.
      // 일단 살려둠
      if (!resultWords.contains(w)) resultWords.add(w);
      continue;
    }
    
    // 이전에 들어간 단어 중 나와 매우 유사한 단어가 있는지 확인
    bool isDuplicate = false;
    for (final existing in resultWords) {
      if (existing == w) {
        isDuplicate = true;
        break;
      }
      // '두산위브트레지움아파트'가 있는데 '곡동두산위브트레지움'이 들어오려는 경우 (유사도 검사)
      if (existing.length >= 5 && w.length >= 5) {
        // 공통 부분이 5글자 이상이면 중복으로 간주하고 버림 (뒤에 오는 것을 버림)
        final wSub = w.substring(0, 5);
        final wSub2 = w.substring(w.length - 5);
        if (existing.contains(wSub) || existing.contains(wSub2)) {
          isDuplicate = true;
          break;
        }
      }
    }
    if (!isDuplicate) {
      resultWords.add(w);
    }
  }
  
  return resultWords.join(' ').trim();
}

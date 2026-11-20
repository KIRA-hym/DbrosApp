/// 콜카드 주소 OCR 공통 전처리 - UI 노이즈 제거·지하 층수 오인식 보정.

final RegExp _carrierBuildingGuardRegex = RegExp(
  r'(?:SKT|SKTelecom|SK\s*Telecom|SK텔레콤|에스케이텔레콤|KT|LG\s*U\+|LGU\+)\s*(?:타워|빌딩|사옥|본사|지사|지점|대리점|직영점|매장|센터|프라자|플라자|파크|스퀘어|광화문|분당)',
  caseSensitive: false,
);

/// 안드로이드 상단 상태바·통신사 표기 줄인지 판별 (`SKT`, `SKT 5G`, `SKT 오전 1:20`, `SKT T전화` 등).
/// `SKT타워`, `SKT 대리점` 등 실제 건물/상호명 줄은 false를 반환하여 보호합니다.
bool isCarrierStatusBarNoiseLine(String line) {
  final t = line.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return false;
  if (_carrierBuildingGuardRegex.hasMatch(t)) return false;

  // 광역 행정구역이나 상세 주소 단위(동/읍/면/리/로/길 + 숫자 등)가 함께 있으면 상태바 단독 줄이 아님
  if (RegExp(
    r'(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)\s+[가-힣]+(?:시|군|구)',
  ).hasMatch(t)) {
    return false;
  }

  // 1) 통신사 단독 또는 통신사 + 네트워크/시계/날짜/배터리/T전화/통화상태 메타 조합
  const statusTokens =
      r'(?:SKT|SKTelecom|SK\s*Telecom|에스케이텔레콤|KT|olleh|LG\s*U\+|LGU\+|U\+|'
      r'5G|LTE|LTE\+|VoLTE|HD\s*Voice|HD|Wi-?Fi|NFC|GPS|TALK|'
      r'T\s*전화|안심통화|통화중|부재중|통화\s*녹음|로밍|'
      r'오전|오후|\d{1,2}[:：.]\d{2}|\d{1,2}시\s*\d{0,2}분?|\d{1,2}월\s*\d{1,2}일(?:\s*\([월화수목금토일]\))?|'
      r'\d{1,3}%|[·•|/:,\-\(\)])';

  // 통신사 키워드가 하나 이상 포함된 순수 상태바 줄
  final hasCarrier = RegExp(
    r'(?:^|[\s·•|/(\[])(?:SKT|SKTelecom|SK\s*Telecom|에스케이텔레콤|LG\s*U\+|LGU\+|KT(?=\s*(?:$|5G|LTE|VoLTE|HD|olleh|\d{1,2}[:：.]|오전|오후|\d{1,3}%))|T\s*전화)(?:$|[\s·•|/)\]])',
    caseSensitive: false,
  ).hasMatch(t);

  if (hasCarrier) {
    final fullStatusRe = RegExp('^\\s*(?:$statusTokens\\s*)+\\s*\$', caseSensitive: false);
    if (fullStatusRe.hasMatch(t)) return true;
  }

  return false;
}

/// 주소 문자열 맨 앞/뒤에 상태바 통신사 토큰(`SKT`, `SKTelecom`, `SKT 5G` 등)이
/// 붙어 들어온 경우만 안전하게 제거합니다. (`SKT타워`, `SKT 대리점` 등은 보존)
String stripCarrierStatusNoiseTokens(String s) {
  var res = s.trim();
  if (res.isEmpty) return '';
  if (isCarrierStatusBarNoiseLine(res)) return '';

  // 앞단 통신사 + 상태바 메타 제거 (뒤에 건물명 키워드가 바로 오는 경우는 제외)
  final leadingRe = RegExp(
    r'^(?:(?:SKT|SKTelecom|SK\s*Telecom|에스케이텔레콤|LG\s*U\+|LGU\+)(?=\s+(?!(?:타워|빌딩|사옥|본사|지사|지점|대리점|직영점|매장|센터|프라자|플라자|파크|스퀘어)\b))(?:\s+(?:5G|LTE|LTE\+|VoLTE|HD\s*Voice|HD|T\s*전화|오전|오후|\d{1,2}[:：.]\d{2}|\d{1,2}월\s*\d{1,2}일|\d{1,3}%))*)\s+',
    caseSensitive: false,
  );
  res = res.replaceFirst(leadingRe, '').trim();

  // 후미 단독 통신사 상태바 토큰 제거 (예: "... 202동주차장 SKT", "... 역삼동 SKT 5G")
  final trailingRe = RegExp(
    r'\s+(?:SKT|SKTelecom|SK\s*Telecom|에스케이텔레콤|LG\s*U\+|LGU\+)(?:\s+(?:5G|LTE|LTE\+|VoLTE|HD\s*Voice|HD|T\s*전화|\d{1,3}%))*\s*$',
    caseSensitive: false,
  );
  res = res.replaceFirst(trailingRe, '').trim();

  return res.replaceAll(RegExp(r'\s+'), ' ').trim();
}

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
  res = stripCarrierStatusNoiseTokens(res);
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

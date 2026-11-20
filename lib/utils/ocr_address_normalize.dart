// 콜카드 주소 OCR 공통 전처리 - 통신사 상태바·플로팅 오버레이·안내 배너 제거 및 지하 층수 오인식 보정.

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

final RegExp _floatingAppStrongTokenRe = RegExp(
  r'(?:^|\s)(?:LOGI|TALK|kakao|TMAP|기사용|콜마너|로지)(?=\s|$)',
  caseSensitive: false,
);

final RegExp _floatingAppOnlyLineRe = RegExp(
  r'^(?:(?:LOGI|TALK|D2|kakao|TMAP|대리|기사용|기사님|콜마너|로지|T대리|카카오)(?:\s+|$))+$',
  caseSensitive: false,
);

/// 화면 가장자리의 플로팅 앱 전환 오버레이 아이콘 텍스트 줄인지 판별
/// 예) `대리 LOGI TALK D2 기사용 기사님 kakao`, `LOGI TALK`
bool isFloatingAppOverlayNoiseLine(String line) {
  final t = line.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return false;
  if (!_floatingAppOnlyLineRe.hasMatch(t)) return false;
  final tokens = t.split(' ');
  return tokens.length >= 2 || _floatingAppStrongTokenRe.hasMatch(t);
}

/// 주소 꼬리에 붙은 플로팅 앱 오버레이 아이콘 텍스트를 안전하게 제거합니다.
/// (`SKT 대리점` 등 정상 상호명은 절대 건드리지 않습니다.)
String stripFloatingAppOverlayNoise(String s) {
  var res = s.trim();
  if (res.isEmpty) return '';
  if (isFloatingAppOverlayNoiseLine(res)) return '';

  // 꼬리에 플로팅 앱 토큰이 2개 이상 연속되거나(예: `대리 LOGI TALK D2 기사용 기사님 kakao`),
  // 영문 앱명(`LOGI`, `TALK`, `kakao`, `TMAP`)이 단독 토큰으로 붙은 경우 제거
  final trailingClusterRe = RegExp(
    r'\s+((?:(?:LOGI|TALK|D2|kakao|TMAP|대리|기사용|기사님|콜마너|로지|T대리)\s*)+)$',
    caseSensitive: false,
  );
  final m = trailingClusterRe.firstMatch(res);
  if (m != null) {
    final tail = m.group(1)!.trim();
    final tailTokens = tail.split(RegExp(r'\s+'));
    final hasStrong = _floatingAppStrongTokenRe.hasMatch(tail);
    if (tailTokens.length >= 2 || hasStrong) {
      res = res.substring(0, m.start).trim();
    }
  }

  return res.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 콜카드 공통 안내 배너·운행 대기 UI·기사 지시 메모 줄인지 판별합니다.
/// 단, `상세:`나 광역 행정주소가 같은 줄에 섞여 있는 경우 줄 전체를 버리지 않고 false를 반환하여
/// 이후 `stripCommonCallCardBannerNoise()`가 뒤쪽 노이즈만 정밀 절삭하도록 보호합니다.
bool isCommonCallCardBannerNoiseLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  // 콜마너 최상단 현재위치+잔액 상태바(`위치 : ... 잔액 : 134,664원`)는 항상 제외
  if (RegExp(r'잔액\s*[:：]').hasMatch(t)) return true;

  // 같은 줄에 실제 주소가 함께 있는 경우 줄 전체를 삭제하지 않음
  if (t.startsWith('상세:') ||
      RegExp(
        r'(?:서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)\s+[가-힣]+(?:시|군|구)',
      ).hasMatch(t)) {
    return false;
  }

  final compact = t.replaceAll(RegExp(r'\s+'), '');
  if (compact.contains('자동설정된주소')) return true;
  if (compact.contains('출발전고객과정확한목적지')) return true;
  if (compact.contains('세부주소나건물명이필요')) return true;
  if (compact.contains('중간대기') || compact.contains('출발대기')) return true;
  if (compact.contains('킥&휠금지') || compact.contains('전동휠절대금지') || compact.contains('전동힐절대금지')) return true;
  if (compact.contains('세미이상필수')) return true;
  if (compact.contains('근처기사만')) return true;
  if (compact.contains('호출앱기사') || compact.contains('호출앱기자')) return true;
  return false;
}

/// 주소 문자열 내부/꼬리에 혼입된 콜카드 안내 배너·대기 UI·기사 지시 메모를 안전하게 절삭합니다.
String stripCommonCallCardBannerNoise(String s) {
  var res = s.trim();
  if (res.isEmpty) return '';
  res = stripFloatingAppOverlayNoise(res);
  // 목적지 자동 설정 안내 배너
  res = res.replaceAll(RegExp(r'\s*자동\s*설정된\s*주소.*$'), '');
  res = res.replaceAll(RegExp(r'\s*출발\s*전\s*고객과.*$'), '');
  res = res.replaceAll(RegExp(r'\s*세부\s*주소나\s*건물명이.*$'), '');
  // 운행 대기 상태 UI
  res = res.replaceAll(RegExp(r'\s*중간\s*대기\s*[:：]?.*$'), '');
  res = res.replaceAll(RegExp(r'\s*출발\s*대기\s*[:：]?.*$'), '');
  res = res.replaceAll(RegExp(r'\s*운행\s*중\s*\(.*$'), '');
  // 콜마너 상단 잔액·법인콜 실탑승자/전화번호/현금0원
  res = res.replaceAll(RegExp(r'\s*잔액\s*[:：]?.*$'), '');
  res = res.replaceAll(RegExp(r'\s*실탑승자\s*[:：]?.*$'), '');
  res = res.replaceAll(RegExp(r'\s*현금\s*[\d,]+\s*원.*$'), '');
  res = res.replaceAll(RegExp(r'\s*01[016789][-\s]?\d{3,4}[-\s]?\d{4}.*$'), '');
  // 기사 지시·금지 메모
  res = res.replaceAll(RegExp(r'\s*\d+\s*분\s*이내\s*근처\s*기사.*$'), '');
  res = res.replaceAll(RegExp(r'\s*근처\s*기사만.*$'), '');
  res = res.replaceAll(RegExp(r'\s*킥\s*&\s*휠\s*금지.*$'), '');
  res = res.replaceAll(RegExp(r'\s*킥보드\s*[,·\s]*전동[휠힐]\s*절대\s*금지.*$'), '');
  res = res.replaceAll(RegExp(r'\s*호출앱\s*기[사자].*$'), '');
  res = res.replaceAll(RegExp(r'\s*(?:1\.\s*)?세미\s*이상\s*필수.*$'), '');
  // 선두 예약 일시 태그 (예: `10 13(화 06:00 S후 `) 및 고아 콜론
  res = res.replaceFirst(
    RegExp(r'^\d{1,2}\s+\d{1,2}\([월화수목금토일]\)?\s*\d{1,2}:\d{2}\s*(?:[A-Za-z]?후)?\s*'),
    '',
  );
  res = res.replaceFirst(RegExp(r'^[:：\s]+'), '');
  res = stripFloatingAppOverlayNoise(res);
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
  res = stripCommonCallCardBannerNoise(res);
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
      if (!resultWords.contains(w)) resultWords.add(w);
      continue;
    }

    bool isDuplicate = false;
    for (final existing in resultWords) {
      if (existing == w) {
        isDuplicate = true;
        break;
      }
      if (existing.length >= 5 && w.length >= 5) {
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

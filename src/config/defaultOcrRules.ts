/**
 * dbros_app 파싱 로직에서 추출한 기본 OCR 룰.
 * - RemoteConfigService 기본값 (region_pattern, kakao_address_pattern)
 * - logi_fare_parse.dart, kakao_call_card_ocr.dart, logi_colmanner_ocr.dart 핵심 패턴
 */
export const DEFAULT_OCR_RULES = {
  version: 2,
  source: 'dbros_app@2026-05-29',
  global: {
    region_pattern:
      '(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)',
    kakao_address_pattern: '^(출발지|도착지|위치|경유지|출발|도착|추천가)\\s*',
  },
  kakao: {
    address_mode: 'line_scan',
    fare_composite_regex: '수익\\s*([\\d,]+)\\s*P\\s*\\+\\s*지원금\\s*([\\d,]+)P?',
    fare_composite_override_regex: '수익\\s*([\\d,]+)\\s*P?\\s*\\+\\s*지원금\\s*([\\d,]+)P?',
    fare_regexes: [
      '법인\\s*([\\d,]{4,})',
      '([\\d,]+)\\s*(?:P|원)',
    ],
    fare_low_threshold: 12000,
    fare_low_multiply_below: 2000,
    start_regex: '출발지\\s*\\n([\\s\\S]*?)\\s*\\n\\s*도착지',
    end_regex: '도착지\\s*\\n([\\s\\S]*?)\\s*\\n\\s*(?:상세|요금|거리|수익|실제수익|확정)',
    waypoint_regex: '^(.+?)\\s+경유(?:\\s*지)?\\s*[:：]?\\s*Q?\\s*$',
    cleanup_rules: [
      { pattern: '(?:♨청방♨|🌟천사|⊙스타|⊙|🌟|♨|🤍|Q)', replace: '', flags: 'g' },
      { pattern: '([가-힣\\s])나(\\d)', replace: '$1 4$2', flags: 'g' },
      { pattern: '^(출발지|도착지|위치|경유지|출발|도착|추천가)\\s*', replace: '', flags: 'i' },
      { pattern: '상세:.*$', replace: '', flags: '' },
      { pattern: '([가-힣]+[동읍면리구시군])\\s*\\)?\\s*\\1', replace: '$1', flags: 'g' },
      { pattern: '\\s+주차$', replace: '', flags: '' },
      {
        pattern: '(?:출\\s*도\\s*경로거리|지도|서명|길안내|배정취소|약\\s*\\d+\\s*분\\s*운행).*$',
        replace: '',
        flags: '',
      },
      { pattern: '고객과\\s*통화|고객과\\s*메시지|출발지에\\s*도착[^.]*', replace: ' ', flags: 'g' },
      { pattern: '\\s{2,}', replace: ' ', flags: 'g' },
    ],
  },
  logi: {
    address_mode: 'line_join_split',
    fare_label_regex: '(?:요\\s*금|요금)\\s*[:：]?\\s*([\\d\\s,oOlLIi\\.그기!sSzZ]+)',
    fare_regexes: ['요금[^\\d]{0,12}([\\d,]{4,7})\\s*원?'],
    fare_i0000_pattern: '^[Il]0{4}$',
    fare_i0000_value: 70000,
    start_regex: '(?:출발지|상세)\\s*[:：]?\\s*([\\s\\S]*?)(?=\\s*(?:도\\s*착\\s*지?|착\\s*지|도착지))',
    end_regex: '(?:도\\s*착\\s*지?|도착지)\\s*[:：]?\\s*([\\s\\S]*?)(?=\\n\\s*(?:완료|배차|경로|갱신|닫기|지도|처리|취소|안내|고객|운행|요금|서명|입금))',
    address_boundary_regex:
      '([가-힣\\d]+(?:동|읍|면|리|로|길|번지|층|호|지하|\\d+(?:-\\d+)?)\\s*(?:[A-Za-z\\d@ⓞ]+)?(?:스타)?)\\s+(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)\\s',
    waypoint_regex: '경유\\s*[:：]?\\s*([^\\n\\]/}\\]]+?)(?:\\s*[/\\]}]|$)',
    cleanup_rules: [
      { pattern: '^[가-힣\\s]*n후\\)?\\s*', replace: '', flags: '' },
      { pattern: '\\[.*?\\]|\\{.*?\\}', replace: ' ', flags: 'g' },
      { pattern: '\\b\\d+[Kk]\\].*$|\\d+분후입금.*$|결재.*$', replace: ' ', flags: '' },
      { pattern: '([가-힣\\d])\\)([가-힣])', replace: '$1 $2', flags: 'g' },
      {
        pattern:
          '\\(?(고객전화|상황실|지사명|고객명|출도|경로거리|배정취소|완료|배차|갱신|닫기|지도|서명|고객위치|길안내)\\)?',
        replace: ' ',
        flags: 'g',
      },
      { pattern: '([가-힣\\s])[그기](\\d)', replace: '$1 7$2', flags: 'g' },
      { pattern: '([가-힣\\s])나(\\d)', replace: '$1 4$2', flags: 'g' },
      { pattern: '기내(\\d+)', replace: '74$1', flags: 'g' },
      { pattern: '지핟|지합', replace: '지하', flags: 'g' },
      { pattern: '^(출발지|도착지|위치|경유지)\\s*', replace: '', flags: 'i' },
      { pattern: '상세\\s*:', replace: '', flags: 'i' },
      { pattern: '([가-힣]+[동읍면리구시군])\\s*\\)?\\s*\\1', replace: '$1', flags: 'g' },
      { pattern: '\\s+주차$', replace: '', flags: '' },
      { pattern: '\\s{2,}', replace: ' ', flags: 'g' },
    ],
  },
  colmanner: {
    address_mode: 'line_join_split',
    fare_label_regex:
      '(?:요\\s*금|요금)\\s*[:：]?\\s*([\\d\\s,oOlLIi\\.그기sSzZ]+)(?:원|\\s)*(?=\\()',
    fare_label_fallback_regex: '(?:요\\s*금|요금)\\s*[:：]?\\s*([\\d\\s,oOlLIi\\.그기sSzZ]+)',
    fare_regexes: [],
    start_regex: '(?:출발지|위치|지사명)\\s*[:：]?\\s*([\\s\\S]*?)(?=\\s*(?:도\\s*착\\s*지?|도착지|요금|현금))',
    end_regex: '(?:도\\s*착\\s*지?|도착지)\\s*[:：]?\\s*([\\s\\S]*?)(?=\\n\\s*(?:요금|현금|출도|적요|지도|갱신))',
    waypoint_regex: '경\\s*유\\s*지\\s*[:：]?\\s*([^\\n)]+)',
    cleanup_rules: [
      { pattern: '^(?:출발지|도착지|출도|적요|지도|고객정보|지사명|위치|\\s)+', replace: '', flags: 'i' },
      { pattern: '([가-힣\\d])\\)([가-힣])', replace: '$1 $2', flags: 'g' },
      { pattern: '([가-힣\\s])[그기](\\d)', replace: '$1 7$2', flags: 'g' },
      { pattern: '합계\\s*[:：].*$|예상\\s*운행수수료.*$', replace: '', flags: '' },
      { pattern: '/\\s*0\\s*$', replace: '', flags: '' },
      { pattern: '([가-힣]+[동읍면리구시군])\\s*\\)?\\s*\\1', replace: '$1', flags: 'g' },
      { pattern: '\\s{2,}', replace: ' ', flags: 'g' },
    ],
  },
} as const;

export type OcrPlatformKey = 'kakao' | 'logi' | 'colmanner';

export const getDefaultOcrRules = (): Record<string, unknown> =>
  JSON.parse(JSON.stringify(DEFAULT_OCR_RULES));

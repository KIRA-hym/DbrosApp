import { OcrPlatformKey } from '../config/defaultOcrRules';

export interface ParseResult {
  fare: string;
  start: string;
  end: string;
  waypoints: string[];
  debugLog: string[];
}

interface CleanupRule {
  pattern: string;
  replace: string;
  flags?: string;
}

interface PlatformRules {
  address_mode?: 'regex' | 'line_scan' | 'line_join_split';
  fare_regex?: string;
  fare_regexes?: string[];
  fare_composite_regex?: string;
  fare_composite_override_regex?: string;
  fare_label_regex?: string;
  fare_label_fallback_regex?: string;
  fare_low_threshold?: number;
  fare_low_multiply_below?: number;
  fare_i0000_pattern?: string;
  fare_i0000_value?: number;
  start_regex?: string;
  end_regex?: string;
  waypoint_regex?: string;
  address_boundary_regex?: string;
  cleanup_rules?: CleanupRule[];
}

interface OcrRulesDoc {
  version?: number;
  source?: string;
  global?: {
    region_pattern?: string;
    kakao_address_pattern?: string;
  };
  kakao?: PlatformRules;
  logi?: PlatformRules;
  colmanner?: PlatformRules;
}

const REGION_DEFAULT =
  '(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)';

const toInt = (s: string): number => parseInt(s.replace(/,/g, ''), 10) || 0;

/** logi_fare_parse.dart — normalizeLogiFareDigitToken */
const normalizeLogiFareDigitToken = (digits: string): string | null => {
  let val = digits.trim();
  if (!val) return null;
  if (/^[Il]0{4}$/i.test(val)) return '70000';
  if (val.length === 6 && (val.endsWith('1') || val.endsWith('2'))) {
    val = val.substring(0, 5);
  } else if (val.length === 5 && (val.endsWith('1') || val.endsWith('2'))) {
    const raw = parseInt(val, 10);
    if (!Number.isNaN(raw) && raw % 100 !== 0) val = `${val.substring(0, 4)}0`;
  }
  const n = parseInt(val, 10);
  if (Number.isNaN(n) || n < 1000 || n > 999999 || n % 100 !== 0) return null;
  return String(n);
};

/** logi_fare_parse.dart — prepare() */
const prepareLogiFareRaw = (raw: string): string => {
  let s = raw.replace(/,/g, '').replace(/\s/g, '');
  s = s.replace(/원|₩|P/g, '').replace(/!+/g, '');
  if (/^[Il]0{4}$/i.test(s)) return '70000';
  s = s
    .replace(/그/g, '7')
    .replace(/기/g, '7')
    .replace(/o/g, '0')
    .replace(/O/g, '0')
    .replace(/l/g, '1')
    .replace(/L/g, '1')
    .replace(/I/g, '1')
    .replace(/i/g, '1');
  s = s.replace(/(?<=[\d,.])[sS](?=[\d,.])/g, '5');
  s = s.replace(/(?<=[\d,.])[zZ](?=[\d,.])/g, '2');
  s = s.replace(/[\uAC00-\uD7A3]/g, '');
  return s;
};

const parseLogiFareFromOcrText = (raw: string, log: string[]): string | null => {
  const prepared = prepareLogiFareRaw(raw);
  if (prepared === '70000') return '70000';
  const matches = [...prepared.matchAll(/\d{4,6}/g)].map((m) => m[0]);
  if (matches.length === 0) return null;
  matches.sort((a, b) => parseInt(b, 10) - parseInt(a, 10));
  for (const token of matches) {
    const n = normalizeLogiFareDigitToken(token);
    if (n) {
      log.push(`🔧 [로지 요금 토큰] "${token}" → ${n}`);
      return n;
    }
  }
  return null;
};

const injectGlobalPatterns = (rules: OcrRulesDoc): OcrRulesDoc => {
  const region = rules.global?.region_pattern || REGION_DEFAULT;
  const json = JSON.stringify(rules);
  const expanded = json.replace(/\$\{region_pattern\}/g, region);
  return JSON.parse(expanded) as OcrRulesDoc;
};

const applyCleanup = (
  text: string,
  cleanRules: CleanupRule[],
  fieldName: string,
  log: string[],
  extra?: CleanupRule[],
): string => {
  let cleaned = text;
  const all = [...(extra || []), ...cleanRules];
  for (const rule of all) {
    try {
      const flags = rule.flags ?? 'g';
      const rx = new RegExp(rule.pattern, flags);
      const before = cleaned;
      cleaned = cleaned.replace(rx, rule.replace);
      if (before !== cleaned) {
        log.push(`🧹 [${fieldName} 클린업] "${before}" → "${cleaned}"`);
      }
    } catch {
      log.push(`🚨 [클린업 오류] 패턴: ${rule.pattern}`);
    }
  }
  return cleaned.trim();
};

const deduplicateAdjacentTokens = (address: string): string => {
  const words = address.trim().split(/\s+/);
  if (words.length < 2) return address;
  const result: string[] = [];
  for (const word of words) {
    if (result.length === 0) {
      result.push(word);
      continue;
    }
    const last = result[result.length - 1];
    if (word === last) continue;
    if (
      word.startsWith(last) &&
      /(동|읍|면|리|구|시|군)$/.test(last)
    ) {
      result.pop();
      result.push(word);
      continue;
    }
    result.push(word);
  }
  return result.join(' ');
};

// --- Kakao line-scan (kakao_call_card_ocr.dart _parseAddressesFromLines 간소화) ---

const isDateTimeMetaLine = (line: string): boolean => {
  const t = line.trim();
  if (/^\d{1,2}[:：.]\d{1,2}(\s+\d{1,2}월\s*\d{1,2}일)?/.test(t)) return true;
  if (/^\d{1,2}월\s*\d{1,2}일/.test(t)) return true;
  return false;
};

const looksLikeFareAmountLine = (line: string): boolean =>
  /^[\d,]+\s*(P|원)?$/.test(line.trim()) || line.includes('수익') || line.includes('실제수익');

const looksLikeKakaoActionLine = (line: string): boolean =>
  /고객과 통화|고객과 메시지|도착완료|출발지에 도착/.test(line);

const looksLikeAddressLine = (line: string): boolean => {
  const t = line.trim();
  if (t.length < 2 || !/[가-힣]/.test(t)) return false;
  if (isDateTimeMetaLine(t)) return false;
  if (looksLikeFareAmountLine(t)) return false;
  if (looksLikeKakaoActionLine(t)) return false;
  if (/배정취소|제휴콜|무료보험|법인|고객센터|경유/.test(t)) return false;
  if (/^[\d,]+\s*(P|원)?$/.test(t)) return false;
  return true;
};

const parseKakaoAddressesFromLines = (
  rawText: string,
  log: string[],
): { start: string; end: string } => {
  const lines = rawText.replace(/\r\n/g, '\n').split('\n');
  let endIdx = lines.length;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.includes('수익') || line.includes('실제수익') || looksLikeFareAmountLine(line)) {
      endIdx = i;
      break;
    }
  }
  const slice = lines.slice(0, endIdx);
  const addrCandidates: string[] = [];
  for (const line of slice) {
    if (looksLikeAddressLine(line)) addrCandidates.push(line.trim());
  }
  log.push(`🔍 [카카오 줄단위] 주소 후보 ${addrCandidates.length}줄 (요금줄 이전 ${endIdx}줄)`);
  if (addrCandidates.length === 0) return { start: '', end: '' };
  if (addrCandidates.length === 1) return { start: addrCandidates[0], end: '' };
  if (addrCandidates.length >= 4) {
    return {
      start: [addrCandidates[0], addrCandidates[1]].join(' '),
      end: addrCandidates.slice(2).join(' '),
    };
  }
  if (addrCandidates.length === 3) {
    return { start: addrCandidates[0], end: [addrCandidates[1], addrCandidates[2]].join(' ') };
  }
  return { start: addrCandidates[0], end: addrCandidates.slice(1).join(' ') };
};

const parseWaypoint = (rawText: string, regexStr: string | undefined, log: string[]): string => {
  if (!regexStr) return '';
  const lines = rawText.replace(/\r\n/g, '\n').split('\n');
  for (const line of lines) {
    const t = line.trim();
    try {
      const m = new RegExp(regexStr, 'im').exec(t);
      if (m?.[1]) {
        const wp = m[1].trim();
        log.push(`✅ [경유지] "${wp}"`);
        return wp;
      }
    } catch {
      /* skip */
    }
  }
  return '';
};

const splitLogiJoinedAddress = (
  joined: string,
  regionPattern: string,
  boundaryRegexStr: string | undefined,
  log: string[],
): { start: string; end: string } => {
  let text = joined.replace(/[\x00-\x1F\x7F-\x9F]/g, '').replace(/\s+/g, ' ').trim();
  text = text.replace(
    new RegExp(`([가-힣0-9])(${regionPattern})(?=\\s)`, 'g'),
    '$1 $2 ',
  );

  let splitIdx = -1;
  const labelMatch = /(?:^|\s)(도\s*착\s*지?|착\s*지)/.exec(text);
  if (labelMatch) {
    splitIdx = labelMatch.index;
  } else if (boundaryRegexStr) {
    try {
      const boundaryRx = new RegExp(boundaryRegexStr.replace('${region_pattern}', regionPattern));
      const bm = boundaryRx.exec(text);
      if (bm && bm[1] && bm[2]) {
        splitIdx = bm.index + bm[1].length;
        log.push(`🔍 [주소 경계] 광역지명 패턴 분할`);
      }
    } catch {
      /* fallback */
    }
  }
  if (splitIdx === -1) {
    const regionRx = new RegExp(regionPattern, 'g');
    const matches = [...text.matchAll(regionRx)];
    if (matches.length >= 2) {
      for (let i = 1; i < matches.length; i++) {
        if ((matches[i].index ?? 0) > 8) {
          splitIdx = matches[i].index ?? -1;
          break;
        }
      }
    }
  }
  if (splitIdx > 0) {
    let s = text.substring(0, splitIdx).trim();
    let e = text.substring(splitIdx).trim();
    s = s.replace(/^\s*출발지?\s*/, '').replace(/\s*(출발지|도착지|지도)\s*/g, ' ').trim();
    e = e.replace(/^\s*도\s*착\s*지?\s*/, '').replace(/\s*(출발지|도착지|지도)\s*/g, ' ').trim();
    return { start: s, end: e };
  }
  return { start: text.replace(/^\s*출발지?\s*/, '').trim(), end: '' };
};

const parseLogiAddressesFromLines = (
  rawText: string,
  regionPattern: string,
  boundaryRegexStr: string | undefined,
  isColmanner: boolean,
  log: string[],
): { start: string; end: string } => {
  const lines = rawText.replace(/\r\n/g, '\n').split('\n').map((l) => l.trim()).filter(Boolean);
  const buffer: string[] = [];
  let inBlock = false;

  for (const line of lines) {
    const n = line.replace(/\s+/g, '').toLowerCase();
    if (!inBlock) {
      if (n.startsWith('출발지') || new RegExp(`^${regionPattern}`).test(line)) inBlock = true;
      else if (isColmanner && (n.startsWith('지사명') || n.startsWith('고객명') || n.startsWith('위치')))
        inBlock = true;
      else continue;
    }
    if (/요금|현금|완료처리|갱신|닫기/.test(n) && !line.includes('상세:')) break;
    if (/^\d{1,2}:\d{2}$/.test(line) || /\d+\s*분\s*\d+\s*초/.test(line)) continue;
    if (/고객과의\s*거리|0508-\d/.test(line)) continue;
    buffer.push(line);
  }

  const joined = buffer.join(' ');
  log.push(`🔍 [${isColmanner ? '콜마너' : '로지'} 줄결합] ${buffer.length}줄 → "${joined.substring(0, 80)}..."`);
  return splitLogiJoinedAddress(joined, regionPattern, boundaryRegexStr, log);
};

const extractFare = (
  rawText: string,
  platform: OcrPlatformKey,
  rules: PlatformRules,
  log: string[],
): string => {
  let fare = 0;

  if (platform === 'kakao') {
    if (rules.fare_composite_regex) {
      const m = new RegExp(rules.fare_composite_regex, 'i').exec(rawText);
      if (m?.[1] && m[2]) {
        fare = toInt(m[1]) + toInt(m[2]);
        log.push(`✅ [요금] 수익+지원금 합산: ${fare}`);
      }
    }
    if (fare > 0 && rules.fare_composite_override_regex) {
      const om = new RegExp(rules.fare_composite_override_regex, 'i').exec(rawText);
      if (om?.[1] && om[2]) {
        const mathFare = toInt(om[1]) + toInt(om[2]);
        if (mathFare > fare) {
          log.push(`🔧 [요금] override 합산 상향: ${fare} → ${mathFare}`);
          fare = mathFare;
        }
      }
    }
    for (const rxStr of rules.fare_regexes || []) {
      if (fare > 0) break;
      const m = new RegExp(rxStr, 'i').exec(rawText);
      if (m?.[1]) {
        const v = toInt(m[1]);
        if (v > 0 && (rxStr.includes('법인') ? v % 100 === 0 : true)) {
          fare = v;
          log.push(`✅ [요금] 패턴 매칭: ${fare}`);
        }
      }
    }
    const threshold = rules.fare_low_threshold ?? 12000;
    const multBelow = rules.fare_low_multiply_below ?? 2000;
    if (fare > 0 && fare < threshold && fare < multBelow) {
      const corrected = fare * 10;
      log.push(`🔧 [카카오 저요금 보정] ${fare} → ${corrected}`);
      fare = corrected;
    }
    return fare > 0 ? String(fare) : '0';
  }

  // logi / colmanner
  const flatLines = rawText
    .split(/[\r\n]+/)
    .filter((l) => {
      const t = l.replace(/\s/g, '');
      return !t.includes('입금') && !t.includes('차감') && !t.includes('수익') && !t.includes('잔액');
    })
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();

  const labelRx = platform === 'colmanner' ? rules.fare_label_regex : rules.fare_label_regex;
  if (labelRx) {
    const m = new RegExp(labelRx, 'i').exec(flatLines);
    if (m?.[1]) {
      const parsed = parseLogiFareFromOcrText(m[1], log);
      if (parsed) return parsed;
    }
  }
  if (platform === 'colmanner' && rules.fare_label_fallback_regex) {
    const m2 = new RegExp(rules.fare_label_fallback_regex, 'i').exec(flatLines);
    if (m2?.[1]) {
      const parsed = parseLogiFareFromOcrText(m2[1], log);
      if (parsed) return parsed;
    }
  }
  for (const rxStr of rules.fare_regexes || []) {
    const m = new RegExp(rxStr, 'i').exec(rawText);
    if (m?.[1]) {
      const parsed = parseLogiFareFromOcrText(m[1], log);
      if (parsed) return parsed;
    }
  }
  if (rules.fare_regex) {
    const m = new RegExp(rules.fare_regex, 'si').exec(rawText);
    if (m?.[1]) {
      const parsed = parseLogiFareFromOcrText(m[1], log);
      if (parsed) return parsed;
    }
  }
  return '0';
};

const extractWithRegex = (
  fieldName: string,
  rawText: string,
  regexStr: string | undefined,
  log: string[],
): string => {
  if (!regexStr) {
    log.push(`⏭️ [${fieldName}] 정규식 미설정 — 스킵`);
    return '';
  }
  try {
    const rx = new RegExp(regexStr, 'si');
    log.push(`🔍 [${fieldName}] 적용 패턴: ${regexStr}`);
    const match = rx.exec(rawText);
    if (match?.[1]) {
      const extracted = match[1].trim().replace(/\n/g, ' ');
      log.push(`✅ [${fieldName}] 매칭 성공: "${extracted.substring(0, 80)}${extracted.length > 80 ? '...' : ''}"`);
      return extracted;
    }
    log.push(`❌ [${fieldName}] 매칭 실패`);
    return '';
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    log.push(`🚨 [${fieldName}] 정규식 컴파일 오류: ${msg}`);
    return '';
  }
};

export const parseOcrText = (
  rawText: string,
  rulesJson: string,
  platform: OcrPlatformKey = 'kakao',
): ParseResult => {
  const result: ParseResult = { fare: '0', start: '', end: '', waypoints: [], debugLog: [] };

  if (!rawText?.trim()) {
    result.debugLog.push('⚠️ 원본 텍스트가 비어 있습니다.');
    return result;
  }

  try {
    const rules = injectGlobalPatterns(JSON.parse(rulesJson) as OcrRulesDoc);
    const platformRules = rules[platform];

    if (!platformRules) {
      result.debugLog.push(`⚠️ [${platform}] 규칙이 JSON에 존재하지 않습니다.`);
      return result;
    }

    const regionPattern = rules.global?.region_pattern || REGION_DEFAULT;
    const kakaoLabelCleanup: CleanupRule[] = rules.global?.kakao_address_pattern
      ? [{ pattern: rules.global.kakao_address_pattern, replace: '', flags: 'im' }]
      : [];

    result.debugLog.push(`--- [${platform.toUpperCase()}] 파싱 시작 (dbros_app 룰 엔진 v${rules.version ?? 1}) ---`);

    result.fare = extractFare(rawText, platform, platformRules, result.debugLog);

    const mode = platformRules.address_mode ?? 'regex';
    let startRaw = '';
    let endRaw = '';

    if (platform === 'kakao' && mode === 'line_scan') {
      const addr = parseKakaoAddressesFromLines(rawText, result.debugLog);
      startRaw = addr.start;
      endRaw = addr.end;
      if (!startRaw && platformRules.start_regex) {
        result.debugLog.push('↩️ [출발지] 줄스캔 실패 → start_regex 폴백');
        startRaw = extractWithRegex('출발지', rawText, platformRules.start_regex, result.debugLog);
      }
      if (!endRaw && platformRules.end_regex) {
        result.debugLog.push('↩️ [도착지] 줄스캔 실패 → end_regex 폴백');
        endRaw = extractWithRegex('도착지', rawText, platformRules.end_regex, result.debugLog);
      }
    } else if (mode === 'line_join_split') {
      const addr = parseLogiAddressesFromLines(
        rawText,
        regionPattern,
        platformRules.address_boundary_regex,
        platform === 'colmanner',
        result.debugLog,
      );
      startRaw = addr.start;
      endRaw = addr.end;
      if (!startRaw && platformRules.start_regex) {
        startRaw = extractWithRegex('출발지', rawText, platformRules.start_regex, result.debugLog);
      }
      if (!endRaw && platformRules.end_regex) {
        endRaw = extractWithRegex('도착지', rawText, platformRules.end_regex, result.debugLog);
      }
    } else {
      startRaw = extractWithRegex('출발지', rawText, platformRules.start_regex, result.debugLog);
      endRaw = extractWithRegex('도착지', rawText, platformRules.end_regex, result.debugLog);
    }

    const wp = parseWaypoint(rawText, platformRules.waypoint_regex, result.debugLog);
    if (wp) result.waypoints = [wp];

    const extraCleanup = platform === 'kakao' ? kakaoLabelCleanup : [];
    result.start = deduplicateAdjacentTokens(
      applyCleanup(startRaw, platformRules.cleanup_rules || [], '출발지', result.debugLog, extraCleanup),
    );
    result.end = deduplicateAdjacentTokens(
      applyCleanup(endRaw, platformRules.cleanup_rules || [], '도착지', result.debugLog, extraCleanup),
    );

    result.debugLog.push('--- 파싱 완료 ---');
    result.debugLog.push(`💰 요금: ${result.fare}`);
    result.debugLog.push(`📍 출발지: ${result.start || '-'}`);
    result.debugLog.push(`🏁 도착지: ${result.end || '-'}`);
    if (result.waypoints.length) result.debugLog.push(`🔄 경유: ${result.waypoints.join(', ')}`);
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error);
    result.debugLog.push(`🚨 엔진 전체 오류: ${msg}`);
  }

  return result;
};

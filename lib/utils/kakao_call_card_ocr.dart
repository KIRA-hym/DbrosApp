import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'drive_time_format.dart';
import 'logi_fare_parse.dart';
import 'ocr_address_normalize.dart';

/// 카카오 콜카드 OCR: 프로그램 구분(일반·프콜) + 일반 화면 필드(현금·카드 요금 포함).
class KakaoCallCardOcr {
  KakaoCallCardOcr._();

  static const String programGeneral = '카카오(일반)';
  static const String programPro = '카카오(프콜)';
  /// 일반·2종과 동일 UI로 인식한 뒤, OCR에 `100점` 등이 없으면 제휴로 구분.
  static const String programAlliance = '카카오(제휴)';

  /// 일반 콜카드에 나오는 `100점`·`10점`·`1,500점` 등(제휴 콜에는 보통 없음).
  static final RegExp _driverScorePointsInText = RegExp(
    r'(?<![0-9,])([0-9]{1,5}(?:,[0-9]{3})*|[0-9]{1,5})\s*점(?![0-9])',
  );

  /// [fullText]·블록에 기사 점수 표기가 있으면 true.
  static bool hasCallCardDriverScoreMarker(String fullText, [List<TextBlock>? blocks]) {
    final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (_driverScorePointsInText.hasMatch(flat)) return true;
    if (blocks != null) {
      for (final b in blocks) {
        final t = b.text.trim().replaceAll(',', '');
        if (RegExp(r'^[0-9]{1,5}점$').hasMatch(t)) return true;
      }
    }
    return false;
  }

  /// [detectKakaoProgram] 결과가 `카카오(일반)`일 때만, 점수 표기 부재 시 `카카오(제휴)`.
  static String refineProgramByAllianceHeuristic(
    String fullText,
    List<TextBlock> blocks,
    String detected,
  ) {
    if (detected != programGeneral) return detected;
    if (hasCallCardDriverScoreMarker(fullText, blocks)) return programGeneral;
    return programAlliance;
  }

  /// 공백 제거 후 부분 문자열 검사용.
  static String _compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  static bool _assignmentComplete(String n) =>
      n.contains('배정완료') || (n.contains('배정') && n.contains('완료'));

  static bool _tPhone(String n) =>
      n.contains('T전화') || RegExp(r'T.{0,3}전화').hasMatch(n);

  /// 일반 2종 하단 UI·빨간 배정취소 배너 등. `상황실` OCR 누락 시에도 카카오 판별에 사용.
  static bool _hasForm2UiMarkers(String n) {
    if (n.contains('상황실')) return true;
    if (n.contains('고객') && n.contains('메모')) return true;
    if (n.contains('배정취소') && n.contains('잔여') && n.contains('시간')) return true;
    if (n.contains('취소불가')) return true;
    if (n.contains('고객과만날장소') || n.contains('만날장소길찾기')) return true;
    if (n.contains('밀어서고객에게') || n.contains('도착알림')) return true;
    if (n.contains('출발지에도착')) return true;
    return false;
  }

  static bool _hasCorporateInsurance(String n) =>
      n.contains('법인무료보험') || (n.contains('법인') && n.contains('무료보험'));

  /// 인식 순서: 일반 1종 → 프콜 1종 → 프콜 2종 → 일반 2종 → `고객과 통화` 단독.
  /// 해당 없으면 `null` (카카오 아님).
  static String? detectKakaoProgram(String fullText) {
    final n = _compact(fullText);
    if (n.isEmpty) return null;

    final hasCallCustomer = n.contains('고객과통화');
    final assignment = _assignmentComplete(n);
    final tPhone = _tPhone(n);
    final hasOpsCenter = n.contains('운영센터');
    final form2Ui = _hasForm2UiMarkers(n);
    final corporateInsurance = _hasCorporateInsurance(n);

    // 1. 카카오(일반) 1종: 배정 완료 + 고객과 통화
    if (hasCallCustomer && assignment) {
      return programGeneral;
    }

    // 2. 카카오(프콜) 1종: 배정 완료 + 운영센터 (프콜 2종에는 운영센터 없음)
    if (assignment && hasOpsCenter) {
      return programPro;
    }

    // 3. 카카오(프콜) 2종: T 전화 + 2종 UI + 법인 무료보험, 운영센터 없음
    if (tPhone && form2Ui && corporateInsurance && !hasOpsCenter) {
      return programPro;
    }

    // 4. 카카오(일반) 2종: T 전화 + (2종 UI 또는 배정 완료) + 법인 무료보험 없음
    if (tPhone && !hasOpsCenter && !corporateInsurance && (form2Ui || assignment)) {
      return programGeneral;
    }

    // 5. T 전화 헤더 OCR 누락 — 2종 UI + 배정 완료만으로 일반 2종
    if (!hasOpsCenter && !corporateInsurance && form2Ui && assignment) {
      return programGeneral;
    }

    // 6. 배정 완료 OCR 누락 등 — 고객과 통화만으로 일반
    if (hasCallCustomer) {
      return programGeneral;
    }

    // 7. 카카오 T 브랜드·콜카드 공통 문구
    if ((n.contains('카카오T') || n.contains('카카오')) &&
        (assignment || form2Ui || hasCallCustomer)) {
      return programGeneral;
    }

    return null;
  }

  /// `현금 | 확정` 등 현금 배차 UI.
  static bool looksLikeKakaoCashPayment(String fullText) {
    final n = _compact(fullText);
    if (!n.contains('현금')) return false;
    return n.contains('확정') || n.contains('현금|확정');
  }

  static int? _parseCommaInt(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  static Iterable<RegExpMatch> _allMatches(RegExp re, String input) => re.allMatches(input);

  static RegExpMatch? _lastMatch(RegExp re, String input) {
    final all = _allMatches(re, input).toList();
    return all.isEmpty ? null : all.last;
  }

  /// 현금: `수익` 옆 금액(+P), 또는 `수익`+`지원금` 합산.
  /// 한 줄로 붙인 [flat]에서는 **마지막** `수익` 구간을 쓴다(상단 요금·요약과 혼동 방지).
  static int? parseKakaoCashGrossFare(String fullText) {
    final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ');

    final sumPatterns = <RegExp>[
      RegExp(r'수익\s*([\d,]+)\s*P?\s*\+\s*지원금\s*([\d,]+)\s*P?', caseSensitive: false),
      RegExp(r'수익\s*([\d,]+)\s*\+\s*지원금\s*([\d,]+)', caseSensitive: false),
      RegExp(r'수익\s*([\d,]+)[^\d]{0,24}지원금\s*([\d,]+)', caseSensitive: false),
    ];
    for (final re in sumPatterns) {
      final m = _lastMatch(re, flat);
      if (m != null) {
        final a = _parseCommaInt(m.group(1)!);
        final b = _parseCommaInt(m.group(2)!);
        if (a != null && b != null && a + b > 0) {
          final val = a + b;
          if (val % 100 == 0) return val;
        }
      }
    }

    final withP = _lastMatch(RegExp(r'수익\s*([\d,]+)\s*P', caseSensitive: false), flat);
    if (withP != null) {
      final v = _parseCommaInt(withP.group(1)!);
      if (v != null && v > 0 && v % 100 == 0) return v;
    }

    final loose = _lastMatch(RegExp(r'수익\s*([\d,]+)(?:\s|$|원|P)', caseSensitive: false), flat);
    if (loose != null) {
      final v = _parseCommaInt(loose.group(1)!);
      if (v != null && v > 0 && v % 100 == 0) return v;
    }

    return null;
  }

  /// 현금 요금: 주소 블록(상단) 숫자를 피하기 위해 **하단**(`top` 큰 구역) 블록만 본다.
  static int? parseKakaoCashGrossFareFromBlocks(List<TextBlock> sorted) {
    final byDescTop = List<TextBlock>.from(sorted)
      ..sort((a, b) => b.boundingBox.top.compareTo(a.boundingBox.top));

    for (final b in byDescTop) {
      if (b.boundingBox.top < 700) continue;

      final text = b.text.trim();
      if (!text.contains('수익') && !text.contains('P') && !text.contains('원')) continue;

      final sumMatch = RegExp(r'수익\s*([\d,]+)\s*P?\s*\+\s*지원금\s*([\d,]+)').firstMatch(text);
      if (sumMatch != null) {
        final val = _toInt(sumMatch.group(1)!) + _toInt(sumMatch.group(2)!);
        if (val % 100 == 0) return val;
      }
      final withP = RegExp(r'([\d,]+)\s*(?:P|원)').firstMatch(text);
      if (withP != null) {
        final v = _toInt(withP.group(1)!);
        if (v > 0 && v % 100 == 0) return v;
      }
    }
    return null;
  }

  static bool _excludeWaypointMergeNoise(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (RegExp(r'^출발').hasMatch(t)) return true;
    return _excludeFromStartLocation(t);
  }

  /// `경유` 줄 + 그 아래 OCR 블록(출발지 밴드 전까지)을 이어 붙임 — 일반·프콜 공통.
  static String _mergeWaypointFromBlocks(List<TextBlock> sorted) {
    int? startIdx;
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].text.contains('경유')) {
        startIdx = i;
        break;
      }
    }
    if (startIdx == null) return '';

    const startBandY = 500.0;
    final buf = StringBuffer();
    for (var i = startIdx; i < sorted.length; i++) {
      final b = sorted[i];
      final y = b.boundingBox.top;
      if (i > startIdx && y >= startBandY) break;

      final raw = b.text.trim();
      if (i == startIdx) {
        var rest = raw.replaceFirst(RegExp(r'^.*\b경유\s*지?\s*[:：]?\s*', caseSensitive: false), '').trim();
        if (rest.isEmpty || rest == raw) {
          rest = raw.replaceAll(RegExp(r'경유\s*지?'), '').trim();
        }
        if (rest.isNotEmpty) buf.write(rest);
      } else {
        if (_excludeWaypointMergeNoise(raw)) continue;
        if (raw.contains('경유')) continue;
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(raw);
      }
    }
    return buf.toString().trim();
  }

  static bool _excludeFromStartLocation(String text) {
    final t = text.trim();
    if (_isDateTimeMetaLine(t)) return true;
    if (RegExp(r'배정|메뉴|완료|취소').hasMatch(t)) return true;
    return _excludePaymentOrActionStrip(t);
  }

  /// 도착지 밴드에 끼어드는 요금·버튼 줄 제외.
  static bool _excludeFromEndLocation(String text) {
    final t = text.trim();
    if (_looksLikeKakaoActionLine(t)) return true;
    if (_looksLikeFareAmountLine(t)) return true;
    if (t.contains('무료보험') || RegExp(r'^\d+\s*점$').hasMatch(t.replaceAll(',', ''))) {
      return true;
    }
    return _excludePaymentOrActionStrip(text);
  }

  static bool _looksLikeFareAmountLine(String t) {
    final clean = t.trim();
    if (_looksLikeAddressFareTrap(clean)) return false;
    
    if (RegExp(r'^[\d,]+\s*(원|P|p)$').hasMatch(clean)) return true;
    if (clean.contains('예상') && clean.contains('수익')) return true;
    
    if (RegExp(r'^\s*[\d,]+\s*(P|p)$').hasMatch(clean)) return true;
    if (RegExp(r'^\s*\d{1,3},\d{3}\s*$').hasMatch(clean)) return true;
    
    return false;
  }

  static bool _looksLikeAddressFareTrap(String line) {
    return RegExp(r'(번길|번지|로\d|동\s*\d|시\s+[가-힣]+구)').hasMatch(line);
  }

  static bool _shouldSkipFareLine(String line) {
    if (_looksLikeAddressLine(line) && _looksLikeAddressFareTrap(line)) return true;
    return false;
  }

  static bool _isPaymentConfirmationLine(String line) {
    final t = line.trim();
    final compact = _compact(t);
    if ((t.contains('현금') || t.contains('카드')) && t.contains('확정')) return true;
    if (compact.contains('현금|확정') || compact.contains('카드|확정')) return true;
    if (t == '확정' || RegExp(r'^\|\s*확정').hasMatch(t)) return true;
    return false;
  }

  static String _trimTrailingFareSuffix(String address) {
    var t = address.trim();
    t = t.replaceAll(RegExp(r'\s*[\d,]{3,}\s*원?\s*$'), '');
    t = t.replaceAll(RegExp(r'\s*[\d,]{3,}\s*P\s*$', caseSensitive: false), '');
    return t.trim();
  }

  static bool _excludePaymentOrActionStrip(String text) {
    final t = text.trim();
    if (t.length <= 6) {
      const shortUi = {'고객', '메모', '상황실', '운영센터', '메뉴', '기사님', '콜센터'};
      if (shortUi.contains(t)) return true;
    }
    if (t.contains('메모') || t.contains('메뉴') || t.contains('기사님') || t.contains('콜센터')) return true;
    if (t.contains('현금') && t.contains('확정')) return true;
    if (t.contains('카드') && t.contains('확정')) return true;
    if (t.contains('지원금')) return true;
    if (t.contains('수익') && RegExp(r'\d').hasMatch(t)) return true;
    if (t.contains('밀어서') || t.contains('도착알림')) return true;
    if (t.contains('길찾기')) return true;
    if (t.contains('배정취소 가능 잔여 시간')) return true;
    if (t.contains('[취소불가]')) return true;
    if (t.contains('고객과 만날 장소')) return true;
    if (t.contains('위치정보가 공유')) return true;
    final compact = _compact(t);
    if (compact.contains('위치정보') && compact.contains('공유')) return true;
    if (t.contains('스크린샷을 삭제했어요')) return true;
    if (t.contains('통화가 종료되었습니다')) return true;
    return false;
  }

  static List<String> _normalizedLines(String fullText) {
    return fullText
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static int _toInt(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  /// 카카오T 통합 파이프라인 (마스터 구현).
  ///
  /// 요금은 마스터 정규식 그대로. 주소는 동일 화면에서 `확정`만으로는 잘리지 않도록
  /// [수익·실제수익·순수 요금 줄] 이전 구간만 잘라 `_parseAddressesFromLines`로 출발/도착을
  /// 복원한 뒤 [_cleanAddr]로 정제한다.
  static ({String start, String end, int fare, String waypoint}) _parseKakaoT(List<String> lines, String fullText) {
    var fare = 0;

    final cashMatch = RegExp(r'수익\s*([\d,]+)\s*P\s*\+\s*지원금\s*([\d,]+)P?').firstMatch(fullText);
    if (cashMatch != null) {
      fare = _toInt(cashMatch.group(1)!) + _toInt(cashMatch.group(2)!);
    } else {
      final pMatch = RegExp(r'([\d,]+)\s*(?:P|원)').firstMatch(fullText);
      if (pMatch != null) fare = _toInt(pMatch.group(1)!);
    }

    // Override OCR error like 11600 if cashMatch math yields 17600
    if (fare > 0) {
      final overrideMatch = RegExp(r'수익\s*([\d,]+)\s*P?\s*\+\s*지원금\s*([\d,]+)P?', caseSensitive: false).firstMatch(fullText);
      if (overrideMatch != null) {
        final mathFare = _toInt(overrideMatch.group(1)!) + _toInt(overrideMatch.group(2)!);
        if (mathFare > fare) fare = mathFare;
      }
    }

    // Apply Kakao low fare correction rules
    if (fare < 12000) {
      if (fare < 2000) {
        fare = fare * 10;
      }
      if (fare >= 10000 && fare < 12000) {
        final fareStr = fare.toString();
        if (fareStr.startsWith('11')) {
          fare = fare + 6000;
        }
      }
    }

    var endIdx = lines.length;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.contains('수익') || line.contains('실제수익')) {
        endIdx = i;
        break;
      }
      if (_looksLikeFareAmountLine(line)) {
        endIdx = i;
        break;
      }
    }
    final slice = lines.sublist(0, endIdx);
    final waypoint = _parseWaypointFromLines(slice);
    final fromLines = _parseAddressesFromLines(slice);

    return (
      start: _cleanAddr(fromLines.$1),
      end: _cleanAddr(fromLines.$2),
      fare: fare,
      waypoint: waypoint,
    );
  }

  /// 공통 주소 정제 — 카카오T 아이콘·Q 노이즈·하단 UI.
  static String _deduplicateAdjacentTokens(String address) {
    final words = address.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return address;
    final result = <String>[];
    for (final word in words) {
      if (result.isEmpty) {
        result.add(word);
        continue;
      }
      final last = result.last;
      if (word == last) continue;
      if (word.startsWith(last) && (last.endsWith('동') || last.endsWith('읍') || last.endsWith('면') || last.endsWith('리') || last.endsWith('구') || last.endsWith('시'))) {
        result.removeLast();
        result.add(word);
        continue;
      }
      result.add(word);
    }
    return result.join(' ');
  }

  static String _cleanAddr(String s) {
    var res = s.replaceAll(RegExp(r'(?:♨청방♨|🌟천사|⊙스타|⊙|🌟|♨|🤍|⊙스타마곡|Q)'), '').trim();

    res = res.replaceAllMapped(RegExp(r'([가-힣\s])나(\d)'), (m) => '${m.group(1)}4${m.group(2)}');

    res = res.replaceAll(RegExp(r'^(출발지|도착지|위치|경유지|출발|도착|추천가)\s*'), '').trim();
    if (res.contains('상세:')) {
      res = res.split('상세:').last.trim();
    }

    res = stripCallCardUiNoiseTokens(res);
    res = res.replaceAllMapped(RegExp(r'([가-힣]+[동읍면리구시군])\s*\)?\s*\1'), (m) => m.group(1)!);
    
    res = res.replaceAll(RegExp(r'\s+주차$'), '');

    res = normalizeCallCardAddressOcr(
      res.replaceAll(RegExp(r'(?:출\s*도\s*경로거리|지도|서명|길안내|배정취소|약\s*\d+\s*분\s*운행).*$'), ''),
    );

    return _deduplicateAdjacentTokens(res);
  }

  static int _findPaymentLineIndex(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (_isPaymentConfirmationLine(lines[i])) return i;
      if (i + 1 < lines.length) {
        final cur = lines[i];
        final next = lines[i + 1];
        if ((cur.contains('현금') || cur.contains('카드')) && next.contains('확정')) return i;
      }
    }
    for (var i = 0; i < lines.length; i++) {
      if (_looksLikeFareAmountLine(lines[i])) return i;
    }
    return -1;
  }

  static String _normalizeOcrLine(String line) =>
      line.trim().replaceAll('：', ':').replaceAll('．', '.').replaceAll(RegExp(r'\s+'), ' ');

  static bool _hasLeadingClockToken(String line) {
    final t = _normalizeOcrLine(line);
    return RegExp(r'^\d{1,2}[:：.]').hasMatch(t) || RegExp(r'^\d{1,2}시').hasMatch(t);
  }

  /// 상단 운행시간·일자 줄(`19:32 5월 11일`, `19.32` 등). 출발지 후보에서 제외한다.
  static bool _isDateTimeMetaLine(String line) {
    final t = _normalizeOcrLine(line);
    if (t.isEmpty) return false;
    if (RegExp(r'^\d{1,2}[:：.]\d{1,2}(?:\s+\d{1,2}월\s*\d{1,2}일(?:\s+\S+)*)?').hasMatch(t)) {
      return true;
    }
    if (RegExp(r'^\d{1,2}[:：.]\d{1,2}$').hasMatch(t)) return true;
    if (RegExp(r'^\d{1,2}월\s*\d{1,2}일(?:\s+\S+)*$').hasMatch(t)) return true;
    if (RegExp(r'^\d{4}[-./]\d{1,2}[-./]\d{1,2}').hasMatch(t)) return true;
    if (RegExp(r'^\d{1,2}시\s*\d{0,2}분?(?:\s+\d{1,2}월\s*\d{1,2}일)?').hasMatch(t)) return true;
    if (_hasLeadingClockToken(t) && !_looksRegionLike(t)) return true;
    return false;
  }

  static (String?, String?) _extractDriveMetaFromLine(String line) {
    final t = _normalizeOcrLine(line);
    if (t.isEmpty) return (null, null);
    if (!_isDateTimeMetaLine(line) && !_hasLeadingClockToken(line)) return (null, null);

    String? date;
    final iso = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(t);
    if (iso != null) {
      date =
          '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}';
    }

    String? time;
    final colon = RegExp(r'(\d{1,2})[:：.](\d{1,2})').firstMatch(t);
    if (colon != null) {
      time = normalizeDriveTimeHm('${colon.group(1)}:${colon.group(2)}');
    }
    if (time == null) {
      final ko = RegExp(r'(\d{1,2})시\s*(\d{1,2})분?').firstMatch(t);
      if (ko != null) {
        time = normalizeDriveTimeHm('${ko.group(1)}:${ko.group(2)}');
      }
    }

    if (date == null && time == null) return (null, null);
    return (date, time);
  }

  /// 요금·주소 구간 이전 상단에서 처음 나오는 시각·일자를 운행 메타로 쓴다.
  static (String?, String?) _parseDriveMetaFromLines(List<String> lines) {
    final payIdx = _findPaymentLineIndex(lines);
    final bound = payIdx >= 0 ? payIdx : lines.length;
    final scanLimit = bound < 12 ? bound : 12;

    String? parsedDate;
    String? parsedTime;
    for (var i = 0; i < scanLimit; i++) {
      final meta = _extractDriveMetaFromLine(lines[i]);
      if (parsedDate == null && meta.$1 != null) parsedDate = meta.$1;
      if (parsedTime == null && meta.$2 != null) {
        parsedTime = meta.$2;
        break;
      }
    }
    return (parsedDate, parsedTime);
  }

  static bool _looksLikeAddressLine(String line) {
    final t = line.trim();
    if (t.length < 2) return false;
    if (!RegExp(r'[가-힣]').hasMatch(t)) return false;
    if (_isDateTimeMetaLine(t)) return false;
    if (_excludePaymentOrActionStrip(t)) return false;
    if (_looksLikeFareAmountLine(t)) return false;
    if (_looksLikeKakaoActionLine(t)) return false;
    if (RegExp(r'^\d+\s*점$').hasMatch(t.replaceAll(',', ''))) return false;
    if (RegExp(r'^[\d,]+\s*(P|원)?$').hasMatch(t)) return false;
    if (t.contains('배정취소') || t.contains('배정 완료') || t.contains('제휴콜') || t.contains('메뉴')) return false;
    if (t.contains('무료보험') || t.contains('법인')) return false;
    if (t.contains('고객센터') || t.contains('사고신고') || t.contains('운행중')) return false;
    if (t.contains('경유')) return false;
    if (RegExp(r'[a-zA-Z]{2,}\d+').hasMatch(t) || RegExp(r'\d+[a-zA-Z]{2,}').hasMatch(t)) return false;
    if (RegExp(r'[a-zA-Z]\s*lI|lI\s*[a-zA-Z]').hasMatch(t)) return false;
    return true;
  }

  static bool _looksLikeKakaoActionLine(String line) {
    if (line.contains('고객과 통화')) return true;
    if (line.contains('고객과 메시지')) return true;
    if (line.contains('도착완료')) return true;
    if (line.contains('도착하시면')) return true;
    if (line.contains('출발지에 도착')) return true;
    return false;
  }

  static String _sanitizeKakaoAddress(String address) {
    var t = address.trim();
    if (t.isEmpty) return '';
    const phrases = [
      '고객과 통화',
      '고객과 메시지',
      '출발지에 도착하시면 도착완료 해주세요.',
      '도착완료 해주세요.',
      '고객에게 위치정보가 공유됩니다.',
      '고객에게 위치정 보가 공유됩니다',
      '위치정보가 공유됩니다.',
    ];
    for (final phrase in phrases) {
      t = t.replaceAll(phrase, ' ');
    }
    t = t.replaceAll(RegExp(r'고객에게\s*위치정\s*보가?\s*공유[^\s]*'), ' ');
    t = t.replaceAll(RegExp(r'고객에게\s*위치정보가\s*공유[^\s]*'), ' ');
    t = t.replaceAll(RegExp(r'고객과\s*통화'), ' ');
    t = t.replaceAll(RegExp(r'출발지에\s*도착[^.]*'), ' ');
    t = t.replaceAll(RegExp(r'\s+경유\s+Q\s*', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\s+Q\s*', caseSensitive: false), ' ');
    
    // 어절 및 단어 중복 지명 제거
    t = t.replaceAllMapped(
      RegExp(r'\b([가-힣\s]+?[동읍면리구시군시구])\s*\)?\s*\1\b'),
      (m) => m.group(1)!,
    );
    t = t.replaceAllMapped(RegExp(r'([가-힣]+[동읍면리구시군])\s*\)?\s*\1'), (m) => m.group(1)!);

    // 끝자리 순수 오더 번호 및 영문/숫자 노이즈 제거
    t = t.replaceAll(RegExp(r'\b\d{6,}\b'), ' ');
    t = t.replaceAll(RegExp(r'\b[a-zA-Z\d.]{2,8}\b\s*$'), ' ');

    // 카카오 매칭률/UI 노이즈 잔해 제거
    t = t.replaceAll(RegExp(r'\b\d{1,3}\s*[lI|%]\s*(?:\(\d{1,2}\))?\b', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\b[oO]\s*\.?\s*[lI|%]\s*\d+\b', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'\b\d{1,3}\s*[lI|%]\s*\d+\b', caseSensitive: false), ' ');

    t = stripCallCardUiNoiseTokens(t);
    return normalizeCallCardAddressOcr(t);
  }

  static bool _looksRegionLike(String line) {
    return RegExp(r'(시|군|구|동|읍|면|로|길)').hasMatch(line);
  }

  static String _joinAddressParts(Iterable<String> parts) => parts
      .map((e) => e.trim().replaceAll(RegExp(r'[\r\n]+'), ' '))
      .where((e) => e.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isKakaoParkingOrFloorNoiseLine(String line) {
    final t = line.trim();
    if (t.contains('층') || t.contains('지하') || t.contains('동') || t.contains('호')) {
      return false;
    }
    if (RegExp(r'^B\d', caseSensitive: false).hasMatch(t)) return false;
    if (t.length > 8) return false;
    return RegExp(r'^[A-Za-z]\d{1,2}$').hasMatch(t);
  }

  static (String, String) _parseAddressesFromLines(List<String> lines) {
    final addrCandidates = <String>[];
    for (final line in lines) {
      if (_excludePaymentOrActionStrip(line)) continue;
      if (_looksLikeFareAmountLine(line)) break;
      if (_looksLikeAddressLine(line)) addrCandidates.add(line);
    }
    while (addrCandidates.isNotEmpty && _isKakaoParkingOrFloorNoiseLine(addrCandidates.first)) {
      addrCandidates.removeAt(0);
    }
    if (addrCandidates.isEmpty) return ('', '');
    if (addrCandidates.length == 1) return (addrCandidates.first, '');

    // 프콜/일반 1종(출발 2줄 + 도착 2줄) 대응 — 날짜 메타 줄은 후보에서 이미 제외됨
    if (addrCandidates.length >= 4) {
      final start = _joinAddressParts([addrCandidates[0], addrCandidates[1]]);
      final end = _trimTrailingFareSuffix(_joinAddressParts(addrCandidates.skip(2)));
      return (start, end);
    }

    if (addrCandidates.length == 3) {
      if (!_looksRegionLike(addrCandidates[1])) {
        final start = _joinAddressParts([addrCandidates[0], addrCandidates[1]]);
        final end = _trimTrailingFareSuffix(addrCandidates[2]);
        return (start, end);
      }
      final start = addrCandidates.first;
      final end = _trimTrailingFareSuffix(_joinAddressParts(addrCandidates.skip(1)));
      return (start, end);
    }

    final start = addrCandidates.first;
    final end = _trimTrailingFareSuffix(_joinAddressParts(addrCandidates.skip(1)));
    return (start, end);
  }

  static String _parseWaypointFromLines(List<String> lines) {
    final payIdx = _findPaymentLineIndex(lines);
    final bound = payIdx >= 0 ? payIdx : lines.length;
    final found = <String>[];
    for (var i = 0; i < bound; i++) {
      final line = lines[i];
      if (!line.contains('경유')) continue;
      final cleaned = line.replaceAll(RegExp(r'^\s*경유\s*지?\s*[:：]?\s*'), '').trim();
      found.add(cleaned.isEmpty ? line.trim() : cleaned);
    }
    var result = found.join(' ').trim();
    result = result.replaceAll(RegExp(r'\s*경유\s*Q\b', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'\bQ\b', caseSensitive: false), '');
    result = result.replaceAll(RegExp(r'\s+Q$'), '');
    return result.trim();
  }

  static int? _parseCardFareFromLines(List<String> lines) {
    final payIdx = _findPaymentLineIndex(lines);
    if (payIdx >= 0) {
      for (var i = payIdx; i < lines.length; i++) {
        final line = lines[i];
        if (_excludePaymentOrActionStrip(line)) continue;
        if (_shouldSkipFareLine(line)) continue;
        final m = RegExp(
          r'([\d,\.]{4,})\s*(?:P|원)?\b',
          caseSensitive: false,
        ).firstMatch(line);
        if (m != null) {
          final v = _parseCommaInt(m.group(1)!);
          if (v != null && v > 0 && v % 100 == 0) return v;
        }
        final fromNoise = parseLogiFareFromOcrText(line);
        if (fromNoise != null && fromNoise % 100 == 0) return fromNoise;
        if (_isPaymentConfirmationLine(line)) continue;
        final plain = RegExp(
          r'^([\d,\.]{4,})\s*(?:원|P)?\s*$',
          caseSensitive: false,
        ).firstMatch(line.trim());
        if (plain != null) {
          final v = _parseCommaInt(plain.group(1)!);
          if (v != null && v > 0 && v % 100 == 0) return v;
        }
      }
    }
    for (final line in lines.reversed) {
      if (_shouldSkipFareLine(line)) continue;
      final m = RegExp(
        r'([\d,\.]{4,})\s*(?:P|원)?\b',
        caseSensitive: false,
      ).firstMatch(line);
      if (m != null) {
        final v = _parseCommaInt(m.group(1)!);
        if (v != null && v > 0 && v % 100 == 0) return v;
      }
      final fromNoise = parseLogiFareFromOcrText(line);
      if (fromNoise != null && fromNoise % 100 == 0) return fromNoise;
    }
    return null;
  }

  /// 카카오(일반)·카카오(프콜) 동일 레이아웃 가정 — 카드/현금 요금만 다름.
  static KakaoScreenParsed parseScreen(List<TextBlock> blocks, String fullText) {
    String? parsedDate;
    String? parsedTime;
    var parsedWaypoint = '';
    final startBuf = StringBuffer();
    final endBuf = StringBuffer();
    int? parsedIncome;

    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final lines = _normalizedLines(fullText);
    final useKakaoT = detectKakaoProgram(fullText) != null;

    for (var i = 0; i < sorted.length; i++) {
      final b = sorted[i];
      final y = b.boundingBox.top;
      final text = b.text.trim();

      if (i < 12) {
        final meta = _extractDriveMetaFromLine(text);
        if (parsedDate == null && meta.$1 != null) parsedDate = meta.$1;
        if (parsedTime == null && meta.$2 != null) parsedTime = meta.$2;
      }

      if (y < 200) {
        final dateMatch = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(text);
        if (dateMatch != null && parsedDate == null) {
          parsedDate =
              '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}';
        }
        final timeMatch = RegExp(r'\d{1,2}:\d{1,2}').firstMatch(text);
        if (timeMatch != null && parsedTime == null) {
          parsedTime = normalizeDriveTimeHm(timeMatch.group(0)!) ?? timeMatch.group(0)!;
        }
      }

      if (!useKakaoT) {
        if (y > 500 && y < 900 && !_excludeFromStartLocation(text)) {
          startBuf.write('$text ');
        }
        if (y > 900 && y < 1400 && !_excludeFromEndLocation(text)) {
          endBuf.write('$text ');
        }
      }
    }

    final driveMeta = _parseDriveMetaFromLines(lines);
    if (driveMeta.$1 != null) parsedDate = driveMeta.$1;
    if (driveMeta.$2 != null) parsedTime = driveMeta.$2;

    if (useKakaoT) {
      final kt = _parseKakaoT(lines, fullText);
      parsedWaypoint = kt.waypoint;
      if (parsedWaypoint.isEmpty) {
        parsedWaypoint = _mergeWaypointFromBlocks(sorted);
      }
      startBuf
        ..clear()
        ..write(_sanitizeKakaoAddress(kt.start));
      endBuf
        ..clear()
        ..write(_sanitizeKakaoAddress(_trimTrailingFareSuffix(kt.end)));
      parsedIncome = kt.fare > 0 ? kt.fare : null;
      if (parsedIncome == null) {
        if (looksLikeKakaoCashPayment(fullText)) {
          parsedIncome = parseKakaoCashGrossFareFromBlocks(sorted) ?? parseKakaoCashGrossFare(fullText);
        } else {
          parsedIncome = _parseCardFareFromLines(lines);
        }
      }
    } else {
      parsedWaypoint = _parseWaypointFromLines(lines);
      if (parsedWaypoint.isEmpty) {
        parsedWaypoint = _mergeWaypointFromBlocks(sorted);
      }

      final fromLinesAddr = _parseAddressesFromLines(lines);
      if (fromLinesAddr.$1.isNotEmpty) {
        startBuf.clear();
        startBuf.write(_sanitizeKakaoAddress(fromLinesAddr.$1));
      }
      if (fromLinesAddr.$2.isNotEmpty) {
        endBuf.clear();
        endBuf.write(_sanitizeKakaoAddress(_trimTrailingFareSuffix(fromLinesAddr.$2)));
      } else {
        final trimmedEnd = _sanitizeKakaoAddress(_trimTrailingFareSuffix(endBuf.toString().trim()));
        endBuf.clear();
        endBuf.write(trimmedEnd);
      }

      if (looksLikeKakaoCashPayment(fullText)) {
        parsedIncome = parseKakaoCashGrossFareFromBlocks(sorted) ?? parseKakaoCashGrossFare(fullText);
      } else {
        parsedIncome = _parseCardFareFromLines(lines);
      }
    }

    if (parsedIncome == null) {
      for (final b in sorted) {
        final y = b.boundingBox.top;
        final text = b.text.trim();
        if (y > 1400 && text.contains(RegExp(r'\d{3,}'))) {
          if (_shouldSkipFareLine(text)) continue;
          if (RegExp(r'^\d{1,3}점$').hasMatch(text.replaceAll(',', ''))) continue;
          final cleanNum = text.replaceAll(RegExp(r'[^0-9]'), '');
          if (cleanNum.length >= 4) {
            final val = int.tryParse(cleanNum);
            if (val != null && val % 100 == 0) {
              parsedIncome = val;
              break;
            }
          }
        }
      }
    }

    return KakaoScreenParsed(
      driveDateYmd: parsedDate,
      driveTimeHm: parsedTime,
      waypoint: parsedWaypoint,
      startLocation: startBuf.toString().trim(),
      endLocation: endBuf.toString().trim(),
      grossFare: parsedIncome,
    );
  }
}

class KakaoScreenParsed {
  final String? driveDateYmd;
  final String? driveTimeHm;
  final String waypoint;
  final String startLocation;
  final String endLocation;
  final int? grossFare;
  final String? paymentMethod;

  KakaoScreenParsed({
    required this.driveDateYmd,
    required this.driveTimeHm,
    required this.waypoint,
    required this.startLocation,
    required this.endLocation,
    required this.grossFare,
    this.paymentMethod,
  });
}

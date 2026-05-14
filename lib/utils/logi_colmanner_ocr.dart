import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'drive_time_format.dart';
import 'logi_fare_parse.dart';

class PartnerCallParsed {
  final String driveTimeHm;
  final int grossFare;
  final String startLocation;
  final String endLocation;
  final String waypoint;

  const PartnerCallParsed({
    required this.driveTimeHm,
    required this.grossFare,
    required this.startLocation,
    required this.endLocation,
    required this.waypoint,
  });
}

class LogiColmannerOcr {
  LogiColmannerOcr._();

  static PartnerCallParsed parseLogi(String fullText, {List<TextBlock>? blocks}) {
    final lines = _lines(fullText);
    final time = _parseTime(lines, blocks: blocks);
    final fare = _parseFare(lines, blocks: blocks, fullText: fullText, colmanner: false);
    final waypoint = _parseLogiWaypointFromJeoyo(lines);

    final locations = _parseLogiLocationsMerged(lines);

    return PartnerCallParsed(
      driveTimeHm: time,
      grossFare: fare,
      startLocation: locations.start,
      endLocation: locations.end,
      waypoint: waypoint,
    );
  }

  static PartnerCallParsed parseColmanner(String fullText, {List<TextBlock>? blocks}) {
    final lines = _lines(fullText);
    final time = _parseTime(lines, blocks: blocks);
    final fare = _parseFare(lines, blocks: blocks, fullText: fullText, colmanner: true);

    final locations = _parseColmannerLocationsMerged(lines);
    final start = _normalizeAddressChunk(locations.start);
    final end = _stripColmannerRouteDistance(_normalizeAddressChunk(locations.end));
    final waypoint = _parseColmannerWaypoint(lines);

    return PartnerCallParsed(
      driveTimeHm: time,
      grossFare: fare,
      startLocation: start,
      endLocation: end,
      waypoint: waypoint,
    );
  }

  static List<String> _lines(String fullText) {
    return fullText
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String _normalizeKey(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  static String _parseTime(List<String> lines, {List<TextBlock>? blocks}) {
    if (blocks != null && blocks.isNotEmpty) {
      final sorted = List<TextBlock>.from(blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      for (final block in sorted) {
        if (block.boundingBox.top >= 200) break;
        final m = RegExp(r'(\d{1,2})[:：\.](\d{1,2})').firstMatch(block.text);
        if (m != null) {
          final raw = '${m.group(1)}:${m.group(2)}';
          return normalizeDriveTimeHm(raw) ?? raw;
        }
      }
    }

    for (final l in lines.take(3)) {
      final m = RegExp(r'(\d{1,2})[:：\.](\d{1,2})').firstMatch(l);
      if (m != null) {
        final raw = '${m.group(1)}:${m.group(2)}';
        return normalizeDriveTimeHm(raw) ?? raw;
      }
    }
    return '';
  }

  /// 입금·정산 줄 — 총요금(요금) 스캔에서 제외한다.
  static bool _isLogiDepositOrSettlementAmountLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('입금')) return true;
    if (n.startsWith('차감합계') || n.startsWith('입금합계')) return true;
    if (n.contains('예상수익금') || n.contains('예상수의금')) return true;
    return false;
  }

  /// 폴백: 줄이 **4~6자리 총요금 숫자(콤마·공백·끝의 !·원만 허용)** 로만 이루어진 경우만 인정한다.
  static bool _isStrictStandaloneFareDigitsLine(String line) {
    var t = line.trim().replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    t = t.replaceAll(RegExp(r'[!]+'), '').replaceAll(RegExp(r'[원₩lL]+'), '');
    return RegExp(r'^\d{4,6}$').hasMatch(t);
  }

  static int? _strictFareDigitsFromLine(String line) {
    if (!_isStrictStandaloneFareDigitsLine(line)) return null;
    var t = line.trim().replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    t = t.replaceAll(RegExp(r'[!]+'), '').replaceAll(RegExp(r'[원₩lL]+'), '');
    return int.tryParse(t);
  }

  static int? _bestGrossFareFromAdjacentAmountLines(Iterable<String> lines) {
    int? bestStrict;
    for (final raw in lines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (_isLogiDepositOrSettlementAmountLine(trimmed)) continue;
      if (_isLogiCountdownRemainLine(trimmed) || _isLogiFareClassNoiseLine(trimmed)) continue;
      if (RegExp(r'\d{9,}').hasMatch(trimmed)) continue;
      final v = _strictFareDigitsFromLine(trimmed);
      if (v != null && v >= 1000 && v <= 999_999) {
        if (bestStrict == null || v > bestStrict) bestStrict = v;
      }
    }
    return bestStrict;
  }

  static int _parseFare(
    List<String> lines, {
    List<TextBlock>? blocks,
    String? fullText,
    bool colmanner = false,
  }) {
    if (fullText != null && fullText.isNotEmpty) {
      final fromRx = parseGrossFareRegexFromFullText(fullText, colmanner: colmanner);
      if (fromRx != null && fromRx >= 1000 && fromRx <= 999_999) {
        return fromRx;
      }
    }
    for (var i = 0; i < lines.length; i++) {
      final row = lines[i].trim();
      if (!row.startsWith('요금') && _normalizeKey(row) != '요금') continue;
      final l = lines[i];

      final m = RegExp(r'요금[^\d]{0,12}([\d,]{4,7})\s*원?').firstMatch(l);
      if (m != null) {
        final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v > 0) return v;
      }

      final fromLine = parseLogiFareFromOcrText(l);
      if (fromLine != null && fromLine >= 1000) return fromLine;

      final window = <String>[];
      for (var j = i + 1; j < lines.length && j <= i + 22; j++) {
        final trimmed = lines[j].trim();
        if (_isLogiDepositOrSettlementAmountLine(trimmed)) continue;
        if (_isLogiCountdownRemainLine(trimmed) || _isLogiFareClassNoiseLine(trimmed)) continue;
        if (RegExp(r'\d{9,}').hasMatch(trimmed)) continue;
        window.add(lines[j]);
      }
      final best = _bestGrossFareFromAdjacentAmountLines(window);
      if (best != null) return best;
    }

    if (blocks != null && blocks.isNotEmpty) {
      final sorted = List<TextBlock>.from(blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      for (var i = 0; i < sorted.length; i++) {
        final t = sorted[i].text.trim();
        if (!t.startsWith('요금') && _normalizeKey(t) != '요금') continue;
        int? best;
        final ti = sorted[i].text.trim();
        best = _strictFareDigitsFromLine(ti);
        for (var d = -2; d <= 2; d++) {
          if (d == 0) continue;
          final j = i + d;
          if (j < 0 || j >= sorted.length) continue;
          final tj = sorted[j].text.trim();
          final cand = _strictFareDigitsFromLine(tj);
          if (cand != null && cand >= 1000 && (best == null || cand > best)) best = cand;
        }
        if (best != null && best >= 1000) return best;
      }
    }

    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('요금')) continue;
      final row = lines[i].trim();
      if (row.startsWith('요금') || _normalizeKey(row) == '요금') continue;
      final window = <String>[];
      for (var j = i; j <= i + 22 && j < lines.length; j++) {
        final trimmed = lines[j].trim();
        if (_isLogiDepositOrSettlementAmountLine(trimmed)) continue;
        if (_isLogiCountdownRemainLine(trimmed) || _isLogiFareClassNoiseLine(trimmed)) continue;
        if (RegExp(r'\d{9,}').hasMatch(trimmed)) continue;
        window.add(lines[j]);
      }
      final best = _bestGrossFareFromAdjacentAmountLines(window);
      if (best != null) return best;
    }

    return 0;
  }

  static const List<String> _logiEndStops = [
    '고객id',
    '오더번호',
    '차량번호',
    '전화2',
    '전화',
    '고객과의 거리',
    '적요',
  ];

  static int _indexOfLabel(List<String> lines, String label) {
    final key = _normalizeKey(label);
    for (var i = 0; i < lines.length; i++) {
      if (_normalizeKey(lines[i]).startsWith(key)) return i;
    }
    return -1;
  }

  static String _labelRemainder(String line, String label) {
    return line.replaceFirst(RegExp('^\\s*$label\\s*'), '').trim();
  }

  static bool _isLogiStopLine(String line) {
    final n = _normalizeKey(line);
    for (final stop in _logiEndStops) {
      if (n.startsWith(_normalizeKey(stop))) return true;
    }
    if (n.startsWith('지사명') || n.startsWith('고객명')) return true;
    return false;
  }

  static bool _isLogiNoiseLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('요금') || n.startsWith('입금액')) return true;
    if (line.contains('운행시작') || line.contains('운행 시작')) return true;
    if (line.contains('법인명')) return true;
    return false;
  }

  /// "출발지 도착(19분 35초)" 등 픽업 상태 배너 — 주소 수집을 끊지 않고 해당 줄만 건너뛴다.
  static bool _isLogiPickupArrivalStatusBanner(String line) {
    final n = _normalizeKey(line);
    return n.contains('출발지도착') && (n.contains('분') || n.contains('초'));
  }

  static bool _isLogiUiNoiseLine(String line) {
    final n = _normalizeKey(line);
    const exact = {
      '완료',
      '배차',
      '안내',
      '갱신',
      '닫기',
      '처리',
      '취소',
      '지도',
      '서명',
      '경로',
      '출발지',
      '도착지',
    };
    if (exact.contains(n)) return true;
    if (n == '||' || n.startsWith('경로')) return true;
    if (line.contains('운행시작연기')) return true;
    if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(line)) return true;
    if (RegExp(r'^\d+\s*분\s*\d+\s*초').hasMatch(n)) return true;
    if (_isLogiCountdownRemainLine(line)) return true;
    if (_isLogiFareClassNoiseLine(line)) return true;
    return false;
  }

  /// 메뉴에 반복되는 출발지/도착지/지도 라벨 — 주소 블록 수집을 끊지 않는다.
  static bool _isLogiSkippableAddressRelabelLine(String line) {
    final n = _normalizeKey(line);
    return n == '출발지' || n == '도착지' || n == '지도';
  }

  /// 주소 스캔을 종료하는 하단 UI(로지 운행 화면).
  static bool _isLogiAddressBlockFooterLine(String line) {
    final n = _normalizeKey(line);
    const footers = {
      '완료',
      '처리',
      '닫기',
      '취소',
      '갱신',
      '서명',
      '안내',
      '배차',
    };
    if (footers.contains(n)) return true;
    if (n == '||' || n.startsWith('||')) return true;
    if (line.contains('운행시작연기')) return true;
    if (_isLogiCountdownRemainLine(line)) return true;
    if (_isLogiFareClassNoiseLine(line)) return true;
    final t = line.trim();
    if (RegExp(r'^\d{1,2}[:：.]\d{1,2}\s*$').hasMatch(t)) return true;
    return false;
  }

  /// "17분 31초 남음" 등 배차·남은시간 UI.
  static bool _isLogiCountdownRemainLine(String line) {
    if (!line.contains('남음')) return false;
    return RegExp(r'\d+\s*분').hasMatch(line) || RegExp(r'\d+\s*초').hasMatch(line);
  }

  /// "일반 일반" 등 요금/등급만 있는 줄.
  static bool _isLogiFareClassNoiseLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    final n = _normalizeKey(line);
    if (n == '일반일반' || n == '일반' || n == '우선' || n == '프리') return true;
    if (RegExp(r'^일반\s+일반').hasMatch(t)) return true;
    return false;
  }

  static bool _isLogiMemoLineForBody(String line) {
    if (line.contains('상황실연락') || line.contains('상황실 연락')) return true;
    if (line.contains('대기,경유') ||
        line.contains('대기, 경유') ||
        (line.contains('대기') && line.contains('경유'))) {
      return true;
    }
    if (RegExp(r'경유\s*[:：]').hasMatch(line) && !line.contains('상세:')) return true;
    if (line.contains('발생시') && line.contains('종료후')) return true;
    return false;
  }

  static String? _leadingMetroProvinceToken(String line) {
    final t = line.trim();
    final m = RegExp(
      r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)(?=\s)',
    ).firstMatch(t);
    return m?.group(1);
  }

  /// 광역 + 첫 행정 단위(시·군·구·도) — 같은 광역 내 다른 시·구 구분용.
  static String? _provincialCityKey(String line) {
    final t = line.trim();
    final m = RegExp(
      r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)\s+([가-힣\d]+(?:시|군|구|도)?)',
    ).firstMatch(t);
    if (m == null) return null;
    return '${m.group(1)}:${m.group(2)}';
  }

  /// 적요·메모·고객 블록에서 경유만 추출한다.
  static String _parseLogiWaypointFromJeoyo(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final nk = _normalizeKey(lines[i]);
      if (!nk.startsWith('적요') && !nk.startsWith('메모') && !nk.startsWith('고객')) continue;

      final buf = StringBuffer()..write(lines[i]);
      for (var j = i + 1; j < lines.length && j < i + 5; j++) {
        final n2 = _normalizeKey(lines[j]);
        if (n2.startsWith('요금') || n2.startsWith('입금') || n2.startsWith('출발지')) break;
        buf.write(' ');
        buf.write(lines[j]);
      }

      final joined = buf.toString();
      final w = RegExp(
        r'경유\s*[:：]?\s*([^\n\]/}\]]+?)(?:\s*[/\]}]|$)',
        caseSensitive: false,
      ).firstMatch(joined);
      if (w != null && w.group(1)!.trim().isNotEmpty) {
        return w.group(1)!.trim();
      }
    }
    return '';
  }
  /// OCR 붙음 `설렁탕경기` 등 → `설렁탕 경기` 로 보정해 광역 앵커가 잡히게 한다.
  static String _injectSpaceBeforeProvinceToken(String s) {
    return s.replaceAllMapped(
      RegExp(
        r'([가-힣0-9\)\]\}\.])(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)(?=\s)',
      ),
      (m) => '${m[1]} ${m[2]}',
    );
  }

  static bool _colmannerHasAnchorBetweenStartEndLabels(List<String> lines) {
    final si = _indexOfLabel(lines, '출발지');
    final ei = _indexOfLabel(lines, '도착지');
    if (si < 0 || ei < 0 || si >= ei) return false;
    for (var k = si + 1; k < ei; k++) {
      final nk = _normalizeKey(lines[k]);
      if (nk == '출도' || nk.startsWith('적요')) return true;
    }
    return false;
  }

  /// Step B(로지): `상세:` 앞은 상호·경로로 유지하고, 뒤 행정 주소와 [_joinHeadAndTailAfterFirstSangse]로 합친다.
  static String _normalizeAddressChunkPreserveSangse(String chunk) {
    var s = chunk.trim();
    if (s.isEmpty) return '';
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// `상세:`(또는 `상세 :`)가 있으면, 그 **앞**은 출발 상호·경로 등으로 유지하고 **뒤**만 행정 주소로 이어 붙인다.
  static String _joinHeadAndTailAfterFirstSangse(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    final m = RegExp(r'상세\s*:', caseSensitive: false).firstMatch(t);
    if (m == null) return t;
    final head = t.substring(0, m.start).replaceFirst(RegExp(r'^\s*출발지\s*'), '').trim();
    final tail = t.substring(m.end).trim();
    if (head.isEmpty) return tail;
    return '$head $tail'.trim();
  }

  /// Step C/D: 뭉친 주소 문자열에서 출발/도착 절취.
  static ({String start, String end}) _splitFlattenedAddressJoined(
    String joinedText, {
    required bool isColmanner,
  }) {
    var t = joinedText.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = _injectSpaceBeforeProvinceToken(t);
    var splitIndex = -1;

    var labelMatch = RegExp(r'(^|\s)도\s*착\s*지\s').firstMatch(t);
    labelMatch ??= RegExp(r'(^|\s)도\s*착\s*지(?=[가-힣0-9ⓓⓔⓕⓐⓑ])', caseSensitive: false).firstMatch(t);
    labelMatch ??= RegExp(r'(?<![가-힣])도\s*착\s*지(?=\s|[가-힣0-9]|$)', caseSensitive: false).firstMatch(t);
    if (labelMatch != null) {
      final spaced = labelMatch.groupCount >= 1 ? labelMatch.group(1) : null;
      splitIndex = spaced == ' ' ? labelMatch.start + 1 : labelMatch.start;
    }

    final flatKey = t.replaceAll(RegExp(r'\s'), '');
    final hasDestLabel = flatKey.contains('도착지');

    if (splitIndex < 0 && !hasDestLabel) {
      final regionRe = RegExp(
        r'\s(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)\s+[가-힣]+(?:시|군|구)',
      );
      for (final m in regionRe.allMatches(t)) {
        if (m.start < 4) continue;
        final before = t.substring(0, m.start).trimRight();
        if (RegExp(r'출발지\s*$', caseSensitive: false).hasMatch(before)) continue;
        if (RegExp(r'상세\s*:\s*$', caseSensitive: false).hasMatch(before)) continue;
        splitIndex = m.start;
        break;
      }
    }

    if (splitIndex < 0 && !hasDestLabel) {
      final cityRe = RegExp(
        r'\s[가-힣]{2,5}(?:시|군|구)\s+[가-힣]{2,5}(?:동|읍|면|로|길)',
      );
      for (final m in cityRe.allMatches(t)) {
        if (m.start < 8) continue;
        final before = t.substring(0, m.start).trimRight();
        if (RegExp(r'출발지\s*$', caseSensitive: false).hasMatch(before)) continue;
        splitIndex = m.start;
        break;
      }
    }

    // 3순위(콜마너): 광역 생략·붙은 본문 — `OO구` 뒤에 동/로/길 등 두 번째 행정 덩어리가 이어질 때
    if (splitIndex < 0 && !hasDestLabel && isColmanner) {
      final adminTailRe = RegExp(
        r'\s([가-힣]{2,8}구)\s+([가-힣\d][가-힣\d\-]{0,22}(?:동|읍|면|로|길|가)\b)',
      );
      for (final m in adminTailRe.allMatches(t)) {
        if (m.start < 10) continue;
        final before = t.substring(0, m.start).trimRight();
        if (RegExp(r'출발지\s*$', caseSensitive: false).hasMatch(before)) continue;
        if (RegExp(r'상세\s*:\s*$', caseSensitive: false).hasMatch(before)) continue;
        splitIndex = m.start;
        break;
      }
    }

    if (splitIndex < 0 && hasDestLabel) {
      return (start: '', end: '');
    }

    if (splitIndex < 0) {
      return (start: t, end: '');
    }

    var startLoc = t.substring(0, splitIndex).replaceFirst(RegExp(r'^\s*출발지\s*'), '').trim();
    var endLoc = t.substring(splitIndex).trim();
    endLoc = endLoc.replaceFirst(RegExp(r'^\s*도\s*착\s*지\s*', caseSensitive: false), '').trim();

    startLoc = startLoc.replaceAll(RegExp(r'\s*(출발지|도착지|지도)\s*'), ' ').trim();
    endLoc = endLoc.replaceAll(RegExp(r'\s*(출발지|도착지|지도)\s*'), ' ').trim();

    if (!isColmanner) {
      startLoc = _joinHeadAndTailAfterFirstSangse(startLoc);
      endLoc = _joinHeadAndTailAfterFirstSangse(endLoc);
    } else {
      endLoc = endLoc.replaceAll(RegExp(r'출\s*도\s*경로거리\s*[:：]?\s*[^\s]+'), '').trim();
      endLoc = endLoc.replaceAll(RegExp(r'경로거리\s*[:：]?\s*[^\s]+'), '').trim();
      startLoc = startLoc
          .replaceAll(RegExp(r'\s*(출발지|도착지|지도|상세:)\s*'), ' ')
          .trim();
      endLoc = endLoc
          .replaceAll(RegExp(r'\s*(출발지|도착지|지도|상세:)\s*'), ' ')
          .trim();
    }

    return (start: startLoc, end: endLoc);
  }

  /// 출발지 라벨 없이 중간에 두 번째 광역 블록이 끼어든 콜마너 UI 보정.
  static ({String start, String end}) _colmannerAdjustDoubleMetroInDeparture(String start, String end) {
    var s = start.trim();
    final e = end.trim();
    final probe = ' $s';
    final re = RegExp(
      r'\s(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)\s+',
    );
    final matches = re.allMatches(probe).toList();
    if (matches.length < 2) return (start: s, end: e);
    final cut = matches[1].start;
    if (cut <= 0 || cut > probe.length) return (start: s, end: e);
    final tail = probe.substring(cut).trimLeft();
    final firstTok = tail.split(RegExp(r'\s+')).firstWhere((a) => a.isNotEmpty, orElse: () => '');
    if (!_looksLikeDestinationLead(firstTok)) return (start: s, end: e);
    return (start: probe.substring(1, cut).trim(), end: '$tail $e'.trim());
  }

  static int _logiPipelineRegionStart(List<String> lines) {
    var lastHead = -1;
    for (var k = 0; k < lines.length; k++) {
      final nk = _normalizeKey(lines[k]);
      if (nk.startsWith('고객') || nk.startsWith('적요') || nk.startsWith('메모')) {
        lastHead = k;
      }
    }
    final startLbl = _indexOfLabel(lines, '출발지');
    if (startLbl >= 0) {
      return startLbl;
    }
    return lastHead >= 0 ? lastHead + 1 : 0;
  }

  static List<String> _collectLogiAddressLinesForPipeline(List<String> lines) {
    final start = _logiPipelineRegionStart(lines);
    final buf = <String>[];
    for (var k = start; k < lines.length; k++) {
      final line = lines[k];
      final nk = _normalizeKey(line);
      if (_isLogiAddressBlockFooterLine(line)) break;
      if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
      if (nk == '출발지' || nk == '도착지' || nk == '지도') {
        buf.add(line);
        continue;
      }
      if (_isLogiNoiseLine(line) && !line.contains('상세:')) continue;
      if (_isLogiPickupArrivalStatusBanner(line)) continue;
      if (_isLogiMemoLineForBody(line) && !line.contains('상세:')) continue;
      if (_isLogiFareClassNoiseLine(line)) continue;
      if (_isLogiCountdownRemainLine(line)) continue;
      if (_isLogiUiNoiseLine(line)) continue;
      buf.add(line);
    }
    return buf;
  }

  static List<String> _collectColmannerAddressLinesForPipeline(List<String> lines) {
    final buffer = <String>[];
    var inAddressBlock = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final n = _normalizeKey(line);
      final noSpace = line.replaceAll(RegExp(r'\s+'), '');

      if (!inAddressBlock && n.startsWith('출발지')) {
        inAddressBlock = true;
      }
      if (!inAddressBlock) continue;

      if (noSpace.contains('경유지') ||
          noSpace.contains('요금') ||
          noSpace.contains('현금') ||
          noSpace.contains('입금합계') ||
          noSpace.contains('차감합계') ||
          noSpace.contains('예상소요시간') ||
          noSpace.contains('출도경로거리') ||
          noSpace.contains('경로거리')) {
        break;
      }

      if (noSpace == '출도' || noSpace == '적요') continue;
      if (n.startsWith('적요')) continue;

      if (_isColmannerNoiseLine(line)) continue;
      if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;

      buffer.add(line);
    }
    return buffer;
  }

  static ({String start, String end}) _parseLogiLocationsMerged(List<String> lines) {
    if (_countLabels(lines, '출발지') > 1 || _countLabels(lines, '도착지') > 1) {
      return _parseLogiLocationsLegacy(lines);
    }
    final startLblIdx = _indexOfLabel(lines, '출발지');
    final endLblIdx = _indexOfLabel(lines, '도착지');
    if (startLblIdx >= 0 && endLblIdx == startLblIdx + 1) {
      final sRem = _labelRemainder(lines[startLblIdx], '출발지');
      final eRem = _labelRemainder(lines[endLblIdx], '도착지');
      if (sRem.isEmpty && eRem.isEmpty) {
        return _parseLogiLocationsLegacy(lines);
      }
    }
    if (_indexOfLabel(lines, '도착지') < 0) {
      final startChunk = _extractChunk(
        lines,
        startKeys: const ['출발지'],
        endKeys: const ['도착지'],
        hardStopKeys: _logiEndStops,
      );
      final endChunk = _resolveEndChunk(lines);
      return _sanitizeLogiLocations(startChunk, endChunk);
    }
    final rawLines = _collectLogiAddressLinesForPipeline(lines);
    final joined = rawLines.join(' ');
    if (joined.trim().isEmpty) {
      return _parseLogiLocationsLegacy(lines);
    }
    final split = _splitFlattenedAddressJoined(joined, isColmanner: false);
    final flatKey = joined.replaceAll(RegExp(r'\s'), '');
    final hasDestLabel = flatKey.contains('도착지');
    if (split.end.isEmpty && hasDestLabel) {
      return _parseLogiLocationsLegacy(lines);
    }
    if (split.start.isEmpty && split.end.isEmpty) {
      return _parseLogiLocationsLegacy(lines);
    }
    return _sanitizeLogiLocations(split.start, split.end);
  }

  static ({String start, String end}) _parseColmannerLocationsMerged(List<String> lines) {
    final startIdx = _indexOfLabel(lines, '출발지');
    final endIdx = _indexOfLabel(lines, '도착지');
    if (startIdx >= 0 && endIdx == startIdx + 1) {
      final sRem = _labelRemainder(lines[startIdx], '출발지');
      final eRem = _labelRemainder(lines[endIdx], '도착지');
      if (sRem.isEmpty && eRem.isEmpty) {
        return _parseColmannerLocationsLegacy(lines);
      }
    }
    if (_colmannerHasAnchorBetweenStartEndLabels(lines)) {
      return _parseColmannerLocationsLegacy(lines);
    }
    if (startIdx < 0 || endIdx < 0 || startIdx >= endIdx) {
      final startChunk = _extractChunk(
        lines,
        startKeys: const ['출발지'],
        endKeys: const ['도착지'],
        hardStopKeys: _colmannerEndStops,
      );
      final endChunk = _resolveColmannerEndChunk(lines);
      return (start: startChunk, end: endChunk);
    }
    final raw = _collectColmannerAddressLinesForPipeline(lines);
    final joined = raw.join(' ');
    if (joined.trim().isEmpty) {
      return _parseColmannerLocationsLegacy(lines);
    }
    final split = _splitFlattenedAddressJoined(joined, isColmanner: true);
    final flatKey = joined.replaceAll(RegExp(r'\s'), '');
    final hasDestLabel = flatKey.contains('도착지');
    if (split.end.isEmpty && hasDestLabel) {
      return _parseColmannerLocationsLegacy(lines);
    }
    if (split.start.isEmpty && split.end.isEmpty) {
      return _parseColmannerLocationsLegacy(lines);
    }
    final adjusted = _colmannerAdjustDoubleMetroInDeparture(split.start, split.end);
    return (start: adjusted.start, end: adjusted.end);
  }

  static bool _isColmannerAnchorLine(String line) {
    final n = _normalizeKey(line);
    return n == '출도' || n == '적요';
  }

  static String _stripLogiUiTokens(String value) {
    var s = value.trim();
    if (s.isEmpty) return '';
    const tokens = [
      '출발지',
      '완료',
      '배차',
      '안내',
      '갱신',
      '닫기',
      '처리',
      '취소',
      '지도',
      '경로',
      '서명',
      '운행시작연기',
    ];
    for (final token in tokens) {
      s = s.replaceAll(token, ' ');
    }
    s = s.replaceAll(RegExp(r'출발지\s*도착[^ ]*'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _stripColmannerRouteDistance(String value) {
    return value
        .replaceAll(RegExp(r'출\s*도\s*경로거리\s*[:：]?\s*[^\s]+'), '')
        .replaceAll(RegExp(r'경로거리\s*[:：]?\s*[^\s]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isColmannerMemoLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('출도') || n.startsWith('적요')) return true;
    if (line.contains('경로거리')) return true;
    if (RegExp(r'^즉후\)').hasMatch(line)) return true;
    if (RegExp(r'^정장\)').hasMatch(line)) return true;
    if (RegExp(r'^후불').hasMatch(line)) return true;
    if (line.startsWith('(예상')) return true;
    return false;
  }

  static int _lastIndexOfLabel(List<String> lines, String label) {
    final key = _normalizeKey(label);
    var last = -1;
    for (var i = 0; i < lines.length; i++) {
      if (_normalizeKey(lines[i]).startsWith(key)) last = i;
    }
    return last;
  }

  static int _countLabels(List<String> lines, String label) {
    final key = _normalizeKey(label);
    var count = 0;
    for (final line in lines) {
      if (_normalizeKey(line).startsWith(key)) count++;
    }
    return count;
  }

  static ({List<String> start, List<String> end}) _splitLogiAddressBody(List<String> body) {
    if (body.isEmpty) return (start: const [], end: const []);
    if (body.length == 1) return (start: body, end: const []);

    final idxs = <int>[];
    for (var i = 0; i < body.length; i++) {
      if (_leadingMetroProvinceToken(body[i]) != null) idxs.add(i);
    }
    if (idxs.length >= 2) {
      for (var j = 1; j < idxs.length; j++) {
        final a = body[idxs[j - 1]];
        final b = body[idxs[j]];
        final ka = _provincialCityKey(a);
        final kb = _provincialCityKey(b);
        if (ka != null && kb != null && ka != kb) {
          return (start: body.sublist(0, idxs[j]), end: body.sublist(idxs[j]));
        }
      }
    }

    var destStart = body.length;
    for (var i = 1; i < body.length; i++) {
      if (_looksLikeDestinationLead(body[i])) {
        destStart = i;
        break;
      }
    }
    if (destStart < body.length) {
      return (start: body.sublist(0, destStart), end: body.sublist(destStart));
    }
    return (start: body, end: const []);
  }

  static ({List<String> departure, List<String> destination}) _partitionColmannerAfterEnd(
    List<String> lines, {
    String destinationLead = '',
  }) {
    final departure = <String>[];
    final destination = <String>[];
    final leadKey = _normalizeKey(destinationLead);
    var destinationStarted = false;
    for (final line in lines) {
      if (_isColmannerMemoLine(line) || _isCustomerMetaLine(line)) continue;
      final lineKey = _normalizeKey(line);
      if (!destinationStarted &&
          departure.isNotEmpty &&
          (_looksLikeDestinationLead(line) ||
              (leadKey.isNotEmpty && lineKey.contains(leadKey)))) {
        destinationStarted = true;
      }
      if (!destinationStarted) {
        departure.add(line);
      } else {
        destination.add(line);
      }
    }
    return (departure: departure, destination: destination);
  }

  static bool _isOrphanCustomerNumber(String line) {
    return RegExp(r'^\d{3,8}$').hasMatch(line.trim());
  }

  static ({String start, String end}) _parseLogiLocationsLegacy(List<String> lines) {
    final endIdx = _indexOfLabel(lines, '도착지');
    if (endIdx < 0) {
      final startChunk = _extractChunk(
        lines,
        startKeys: const ['출발지'],
        endKeys: const ['도착지'],
        hardStopKeys: _logiEndStops,
      );
      final endChunk = _resolveEndChunk(lines);
      return _sanitizeLogiLocations(startChunk, endChunk);
    }

    final startIdx = _countLabels(lines, '출발지') > 1
        ? _lastIndexOfLabel(lines, '출발지')
        : _indexOfLabel(lines, '출발지');
    if (startIdx < 0 || startIdx >= endIdx) {
      return _parseLogiTrailingAddressBody(lines, endIdx);
    }

    final startLead = _labelRemainder(lines[startIdx], '출발지');
    final endLead = _labelRemainder(lines[endIdx], '도착지');

    final between = <String>[];
    for (var i = startIdx + 1; i < endIdx; i++) {
      final line = lines[i];
      if (_isLogiNoiseLine(line) || _isLogiUiNoiseLine(line)) continue;
      between.add(line);
    }

    final afterEnd = <String>[];
    for (var i = endIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      if (_isLogiPickupArrivalStatusBanner(line)) continue;
      if (_isLogiSkippableAddressRelabelLine(line)) continue;
      if (_isLogiAddressBlockFooterLine(line)) break;
      if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
      if (_isLogiNoiseLine(line) || _isLogiMemoLineForBody(line)) continue;
      if (!_looksLikeAddressLine(line) && !line.contains('상세:')) {
        if (afterEnd.isNotEmpty) break;
        continue;
      }
      afterEnd.add(line);
    }

    final startParts = <String>[];
    final endParts = <String>[];
    if (startLead.isNotEmpty &&
        !_isCustomerMetaLine(startLead) &&
        !_isLogiUiNoiseLine(startLead)) {
      startParts.add(startLead);
    }
    if (endLead.isNotEmpty &&
        !_isCustomerMetaLine(endLead) &&
        !_isOrphanCustomerNumber(endLead) &&
        !_isLogiUiNoiseLine(endLead)) {
      endParts.add(endLead);
    }

    if (afterEnd.isNotEmpty) {
      if (afterEnd.length == 1) {
        startParts.addAll(between);
        endParts.add(afterEnd.single);
      } else if (between.isEmpty) {
        final detailLines = <String>[];
        final body = <String>[];
        for (final line in afterEnd) {
          if (line.contains('상세:')) {
            final cleaned = line.replaceFirst(RegExp(r'^.*상세\s*:\s*'), '').trim();
            if (cleaned.isNotEmpty) detailLines.add(cleaned);
          } else if (!_isLogiMemoLineForBody(line)) {
            body.add(line);
          }
        }
        final split = _splitLogiAddressBody(body);
        startParts.addAll(split.start);
        startParts.addAll(detailLines);
        endParts.addAll(split.end);
      } else {
        final spillover = <String>[];
        final destination = <String>[];
        for (var i = 0; i < afterEnd.length; i++) {
          final line = afterEnd[i];
          final isLast = i == afterEnd.length - 1;
          if (!isLast && _looksLikeDepartureSpillover(line, between)) {
            spillover.add(line);
          } else {
            destination.add(line);
          }
        }
        startParts.addAll(between);
        startParts.addAll(spillover);
        endParts.addAll(destination);
      }
    } else if (between.length > 1) {
      startParts.addAll(between.sublist(0, between.length - 1));
      endParts.add(between.last);
    } else {
      startParts.addAll(between);
    }

    return _sanitizeLogiLocations(startParts.join(' ').trim(), endParts.join(' ').trim());
  }

  static ({String start, String end}) _parseLogiTrailingAddressBody(
    List<String> lines,
    int endIdx,
  ) {
    final lastStart = _lastIndexOfLabel(lines, '출발지');
    final preStart = <String>[];
    final postStart = <String>[];

    for (var i = endIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      final inPostStart = lastStart >= 0 && i > lastStart;
      if (inPostStart) {
        if (_isLogiPickupArrivalStatusBanner(line)) continue;
        if (_isLogiSkippableAddressRelabelLine(line)) continue;
        if (_isLogiAddressBlockFooterLine(line)) break;
        if (_isLogiStopLine(line)) continue;
        if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
        if (_isLogiNoiseLine(line) || _isLogiMemoLineForBody(line)) continue;
        if (!_looksLikeAddressLine(line) && !line.contains('상세:')) continue;
        postStart.add(line);
        continue;
      }
      if (lastStart >= 0 && i >= lastStart) continue;
      if (_isLogiPickupArrivalStatusBanner(line)) continue;
      if (_isLogiUiNoiseLine(line) || _isLogiNoiseLine(line) || _isLogiMemoLineForBody(line)) {
        continue;
      }
      if (_isLogiStopLine(line)) continue;
      if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
      if (!line.contains('상세:') && !_looksLikeAddressLine(line)) continue;
      preStart.add(line);
    }

    final detailLines = <String>[];
    final body = <String>[];
    for (final line in preStart) {
      if (line.contains('상세:')) {
        final cleaned = line.replaceFirst(RegExp(r'^.*상세\s*:\s*'), '').trim();
        if (cleaned.isNotEmpty) detailLines.add(cleaned);
      } else {
        body.add(line);
      }
    }
    for (final line in postStart) {
      if (line.contains('상세:')) {
        final cleaned = line.replaceFirst(RegExp(r'^.*상세\s*:\s*'), '').trim();
        if (cleaned.isNotEmpty) detailLines.add(cleaned);
      } else {
        body.add(line);
      }
    }

    final split = _splitLogiAddressBody(body);
    final startParts = <String>[...detailLines, ...split.start];
    final endParts = <String>[...split.end];
    return _sanitizeLogiLocations(startParts.join(' ').trim(), endParts.join(' ').trim());
  }

  static ({String start, String end}) _sanitizeLogiLocations(String start, String end) {
    var cleanedStart = _stripLogiUiTokens(_normalizeAddressChunkPreserveSangse(start));
    var cleanedEnd = _stripLogiUiTokens(_normalizeAddressChunkPreserveSangse(end));
    cleanedStart = _joinHeadAndTailAfterFirstSangse(cleanedStart);
    cleanedEnd = _joinHeadAndTailAfterFirstSangse(cleanedEnd);
    cleanedStart = cleanedStart
        .replaceAll(RegExp(r'대기,?경유[^ ]*'), ' ')
        .replaceAll(RegExp(r'발생시\s*종료후\s*상황실연락'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_isLogiUiNoiseLine(cleanedEnd) || cleanedEnd == '||') cleanedEnd = '';
    if (cleanedStart.isNotEmpty && _looksLikeCustomerOnly(cleanedStart)) cleanedStart = '';
    if (cleanedEnd.isNotEmpty && _looksLikeCustomerOnly(cleanedEnd)) cleanedEnd = '';
    return (start: cleanedStart, end: cleanedEnd);
  }

  static const List<String> _colmannerEndStops = [
    '경유지',
    '출도',
    '요금',
    '현금',
    '입금합계',
    '차감합계',
    '적요',
    '고객정보',
    '고객위치',
  ];

  static bool _isColmannerStopLine(String line) {
    final n = _normalizeKey(line);
    for (final stop in _colmannerEndStops) {
      if (n.startsWith(_normalizeKey(stop))) return true;
    }
    if (n.startsWith('지사명') || n.startsWith('고객명')) return true;
    if (line.startsWith('(예상소요시간')) return true;
    return false;
  }

  static bool _isColmannerNoiseLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('요금') || n.startsWith('입금액')) return true;
    if (line.contains('고객전화') && line.contains('상황실')) return true;
    if (line.contains('상황실연락처')) return true;
    return false;
  }

  static bool _looksLikeDestinationLead(String line) {
    if (RegExp(
      r'^(서울|경기|인천|대전|대구|부산|광주|울산|세종|제주|강원|충북|충남|전북|전남|경북|경남)',
    ).hasMatch(line)) {
      return true;
    }
    return RegExp(r'^[가-힣]+(시|군|구)').hasMatch(line);
  }

  static bool _shouldSplitColmannerBetweenTail(List<String> between) {
    if (between.length < 2) return false;
    final tail = between.last;
    if (RegExp(r'(경유|후불|즉후|킥보드|🌟|⊙)').hasMatch(tail)) return false;
    return _looksLikeDestinationLead(tail);
  }

  static ({String start, String end}) _parseColmannerLocationsLegacy(List<String> lines) {
    final startIdx = _indexOfLabel(lines, '출발지');
    final endIdx = _indexOfLabel(lines, '도착지');
    if (startIdx < 0 || endIdx < 0 || startIdx >= endIdx) {
      final startChunk = _extractChunk(
        lines,
        startKeys: const ['출발지'],
        endKeys: const ['도착지'],
        hardStopKeys: _colmannerEndStops,
      );
      final endChunk = _resolveColmannerEndChunk(lines);
      return (start: startChunk, end: endChunk);
    }

    final startLead = _labelRemainder(lines[startIdx], '출발지');
    final endLead = _labelRemainder(lines[endIdx], '도착지');

    final between = <String>[];
    for (var i = startIdx + 1; i < endIdx; i++) {
      final line = lines[i];
      if (_isColmannerNoiseLine(line) || _isColmannerAnchorLine(line)) continue;
      between.add(line);
    }

    final afterEnd = <String>[];
    for (var i = endIdx + 1; i < lines.length; i++) {
      final line = lines[i];
      final nk = _normalizeKey(line);
      if (nk == '출도') continue;
      if (nk.contains('출도경로거리') ||
          nk.contains('출도경로') ||
          (nk.contains('출도') && nk.contains('경로거리'))) {
        break;
      }
      if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
      if (_isColmannerNoiseLine(line)) continue;
      if (_isColmannerStopLine(line)) break;
      afterEnd.add(line);
    }

    final startParts = <String>[];
    final endParts = <String>[];
    if (startLead.isNotEmpty && !_isCustomerMetaLine(startLead)) {
      startParts.add(startLead);
    }

    if (_shouldSplitColmannerBetweenTail(between)) {
      startParts.addAll(between.sublist(0, between.length - 1));
      endParts.add(between.last);
      if (endLead.isNotEmpty &&
          !_isCustomerMetaLine(endLead) &&
          !_isOrphanCustomerNumber(endLead)) {
        endParts.add(endLead);
      }
      endParts.addAll(afterEnd);
    } else {
      startParts.addAll(between);
      if (endLead.isNotEmpty &&
          !_isCustomerMetaLine(endLead) &&
          !_isOrphanCustomerNumber(endLead)) {
        endParts.add(endLead);
      }
      if (afterEnd.isNotEmpty) {
        if (between.isEmpty &&
            startParts.isNotEmpty &&
            startLead.length <= 3) {
          final partitioned = _partitionColmannerAfterEnd(
            afterEnd,
            destinationLead: endLead,
          );
          startParts.addAll(partitioned.departure);
          endParts.addAll(partitioned.destination);
        } else if (between.isEmpty && startParts.isEmpty) {
          final partitioned = _partitionColmannerAfterEnd(
            afterEnd,
            destinationLead: endLead,
          );
          startParts.addAll(partitioned.departure);
          endParts.addAll(partitioned.destination);
        } else if (between.isEmpty) {
          endParts.addAll(afterEnd);
        } else {
          endParts.addAll(afterEnd);
        }
      }
    }

    var start = startParts.join(' ').trim();
    var end = endParts.join(' ').trim();
    if (end.isNotEmpty && _looksLikeCustomerOnly(end)) end = '';
    if (start.isNotEmpty && _looksLikeCustomerOnly(start)) start = '';
    return (start: start, end: end);
  }

  static String _resolveColmannerEndChunk(List<String> lines) {
    const endKeys = [
      '경유지',
      '출도',
      '요금',
      '현금',
      '입금합계',
      '차감합계',
      '적요',
      '고객정보',
      '고객위치',
    ];
    final forward = _extractChunk(
      lines,
      startKeys: const ['도착지'],
      endKeys: endKeys,
      hardStopKeys: endKeys,
      skipMetaLines: true,
    );
    final normalized = _normalizeAddressChunk(forward);
    if (normalized.isNotEmpty && !_looksLikeCustomerOnly(normalized)) {
      return forward;
    }

    return _extractChunk(
      lines,
      startKeys: const ['도착지'],
      endKeys: endKeys,
      hardStopKeys: endKeys,
      lookBackLines: 2,
      lookBackStopKeys: const [
        '출발지',
        '요금',
        '입금액',
        '전화',
        '적요',
        '메모',
        '법인',
        '고객',
        '지사명',
        '고객명',
      ],
      skipMetaLines: true,
    );
  }

  static String _resolveEndChunk(List<String> lines) {
    const endKeys = _logiEndStops;
    final forward = _extractChunk(
      lines,
      startKeys: const ['도착지'],
      endKeys: endKeys,
      hardStopKeys: endKeys,
      skipMetaLines: true,
    );
    final normalized = _normalizeAddressChunk(forward);
    if (normalized.isNotEmpty && !_looksLikeCustomerOnly(normalized)) {
      return forward;
    }

    return _extractChunk(
      lines,
      startKeys: const ['도착지'],
      endKeys: endKeys,
      hardStopKeys: endKeys,
      lookBackLines: 2,
      lookBackStopKeys: const ['출발지', '요금', '입금액', '전화', '적요', '메모', '법인', '고객'],
      skipMetaLines: true,
    );
  }

  static bool _looksLikeCustomerOnly(String value) {
    final n = _normalizeKey(value);
    if (_isCustomerMetaLine(value)) return true;
    return RegExp(r'^고객[i1l]?d?\d{3,}$').hasMatch(n);
  }

  static String _extractChunk(
    List<String> lines, {
    required List<String> startKeys,
    required List<String> endKeys,
    required List<String> hardStopKeys,
    int lookBackLines = 0,
    List<String> lookBackStopKeys = const [],
    bool skipMetaLines = false,
  }) {
    final starts = startKeys.map(_normalizeKey).toList();
    final ends = endKeys.map(_normalizeKey).toList();
    final stops = hardStopKeys.map(_normalizeKey).toList();
    final lookBackStops = lookBackStopKeys.map(_normalizeKey).toList();

    int idx = -1;
    for (var i = 0; i < lines.length; i++) {
      final n = _normalizeKey(lines[i]);
      if (starts.any((k) => n.startsWith(k))) {
        idx = i;
        break;
      }
    }
    if (idx < 0) return '';

    final buffer = <String>[];
    if (lookBackLines > 0) {
      for (var j = idx - 1; j >= 0 && j >= idx - lookBackLines; j--) {
        final line = lines[j];
        final n = _normalizeKey(line);
        if (starts.any((k) => n.startsWith(k))) break;
        if (lookBackStops.any((k) => n.startsWith(k))) break;
        if (_isHardStopLine(line, stops: stops, ends: ends)) break;
        if (skipMetaLines && _isCustomerMetaLine(line)) continue;
        if (!_looksLikeAddressLine(line)) continue;
        buffer.insert(0, line);
      }
    }

    final firstLine = lines[idx];
    final startKey = startKeys.first;
    final firstRemainder = firstLine.replaceFirst(RegExp('^\\s*$startKey\\s*'), '').trim();
    if (firstRemainder.isNotEmpty &&
        !(skipMetaLines && _isCustomerMetaLine(firstRemainder))) {
      buffer.add(firstRemainder);
    }

    for (var i = idx + 1; i < lines.length; i++) {
      final line = lines[i];
      final n = _normalizeKey(line);
      if (ends.any((k) => n.startsWith(k))) break;
      if (stops.any((k) => n.startsWith(k))) break;
      if (n.startsWith('지사명') || n.startsWith('고객명')) break;
      if (skipMetaLines && _isCustomerMetaLine(line)) continue;
      buffer.add(line);
    }

    return buffer.join(' ').trim();
  }

  static bool _isHardStopLine(
    String line, {
    required List<String> stops,
    required List<String> ends,
  }) {
    final n = _normalizeKey(line);
    if (ends.any((k) => n.startsWith(k))) return true;
    if (stops.any((k) => n.startsWith(k))) return true;
    if (n.startsWith('지사명') || n.startsWith('고객명')) return true;
    return false;
  }

  static bool _looksLikeDepartureSpillover(String line, List<String> between) {
    if (line.contains('상세')) return true;
    if (RegExp(r'^[ⓓⓐⓑ]법').hasMatch(line)) return true;
    if (between.isNotEmpty && !_looksRegionLike(line)) {
      return line.length <= 28;
    }
    return false;
  }

  static bool _looksRegionLike(String line) {
    return RegExp(r'(시|군|구|동|읍|면|로|길)').hasMatch(line);
  }

  static bool _isCustomerMetaLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('고객id')) return true;
    if (RegExp(r'^고객[i1l]?d').hasMatch(n)) return true;
    if (RegExp(r'^고객d?\d{3,}').hasMatch(n)) return true;
    if (RegExp(r'^고객id\d{3,}$').hasMatch(n)) return true;
    if (n.startsWith('오더번호')) return true;
    if (n.startsWith('차량번호')) return true;
    if (_isOrphanCustomerNumber(line)) return true;
    return false;
  }

  static bool _looksLikeAddressLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('출발지') || n.startsWith('도착지')) return false;
    if (n.startsWith('요금') || n.startsWith('입금액')) return false;
    if (line.length < 4) return false;
    if (_isCustomerMetaLine(line)) return false;
    if (_isLogiCountdownRemainLine(line) || _isLogiFareClassNoiseLine(line)) return false;
    if (_isLogiStopLine(line)) return false;
    if (RegExp(r'^\d{2,3}:\d{2}').hasMatch(line)) return false;
    if (RegExp(r'^\d{4,7}\s*원?$').hasMatch(line)) return false;
    if (line.contains('요금') && RegExp(r'\d{4,}').hasMatch(line)) return false;
    if (line.contains('구') ||
        line.contains('동') ||
        line.contains('시') ||
        line.contains('로') ||
        line.contains('길') ||
        line.contains('읍') ||
        line.contains('면') ||
        line.contains('리') ||
        line.contains(')')) {
      return true;
    }
    return line.length >= 4 && RegExp(r'[가-힣A-Za-z]').hasMatch(line) && !line.contains('운행');
  }

  static String _normalizeAddressChunk(String chunk) {
    var s = chunk.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'상세\s*:\s*'), '');
    return s.trim();
  }

  static String _parseColmannerWaypoint(List<String> lines) {
    for (final line in lines) {
      if (_normalizeKey(line).startsWith('경유지')) {
        final rest = line.replaceFirst(RegExp(r'^.*경유지\s*'), '').trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    return '';
  }
}


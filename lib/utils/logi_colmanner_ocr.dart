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

    final loc = _parseColmannerLocationsMerged(lines);
    var waypoint = loc.waypoint.trim();
    if (waypoint.isEmpty) waypoint = _parseColmannerWaypoint(lines);
    if (waypoint.contains(')')) {
      waypoint = waypoint.split(')').first.trim();
    }
    waypoint = waypoint.replaceAllMapped(RegExp(r'([그기])(\d{2,})'), (m) => '7${m.group(2)}');
    final start = _cleanAddr(loc.start, isLogi: false, isStart: true);
    final end = _cleanAddr(loc.end, isLogi: false, isStart: false);

    return PartnerCallParsed(
      driveTimeHm: time,
      grossFare: fare,
      startLocation: start,
      endLocation: end,
      waypoint: waypoint,
    );
  }

  static List<String> _lines(String fullText) {
    final cleaned = fullText.replaceAll('추바지', '출발지').replaceAll('도차지', '도착지');
    return cleaned
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
    final fromOcr = parseLogiFareFromOcrText(line);
    if (fromOcr != null) return fromOcr;
    if (!_isStrictStandaloneFareDigitsLine(line)) return null;
    var t = line.trim().replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
    t = t.replaceAll(RegExp(r'[!]+'), '').replaceAll(RegExp(r'[원₩]+'), '');
    return normalizeLogiFareDigitToken(t);
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

  /// 로지 입금액 스택에 보이는 금액(플랫폼 수수료, 약 총요금의 20%)인지 판별한다.
  static bool _isLikelyLogiPlatformFeeAmount(int amount) {
    if (amount < 3000 || amount > 15000) return false;
    if (amount % 1000 != 0) return false;
    final gross = amount * 5;
    return gross >= 10000 && gross <= 999_999;
  }

  /// 수수료만 OCR된 경우 총요금(수수료×5)을 복원한다.
  static int? _inferLogiGrossFareFromPlatformFee(int feeCandidate) {
    if (!_isLikelyLogiPlatformFeeAmount(feeCandidate)) return null;
    return feeCandidate * 5;
  }

  /// 로지 상단 **요금 / 입금액** 영역의 금액 스택에서 총요금을 고른다.
  static int? _grossFareFromLogiFareDepositStack(List<String> lines) {
    if (_indexOfLabel(lines, '요금') < 0 && _indexOfLabel(lines, '입금액') < 0) {
      return null;
    }

    var inSection = false;
    final amounts = <int>[];
    for (final trimmed in lines) {
      if (trimmed.isEmpty) continue;
      final nk = _normalizeKey(trimmed);
      if (nk.startsWith('요금') || nk.startsWith('입금액')) {
        inSection = true;
        final inline = parseLogiFareFromOcrText(trimmed);
        if (inline != null && inline >= 1000) amounts.add(inline);
        continue;
      }
      if (!inSection) continue;

      if (_isLogiFareClassNoiseLine(trimmed)) {
        if (amounts.isNotEmpty) break;
        continue;
      }
      if (RegExp(r'^0508-\d').hasMatch(trimmed) ||
          trimmed.contains('상세:') ||
          RegExp(r'고객과의\s*거리').hasMatch(trimmed)) {
        if (amounts.isNotEmpty) break;
        continue;
      }
      if (_isLogiCountdownRemainLine(trimmed) || _isLogiDepositOrSettlementAmountLine(trimmed)) {
        continue;
      }
      if (RegExp(r'\d{9,}').hasMatch(trimmed)) continue;

      final v = _strictFareDigitsFromLine(trimmed) ?? parseLogiFareFromOcrText(trimmed);
      if (v != null && v >= 1000 && v <= 999_999 && !amounts.contains(v)) {
        amounts.add(v);
      }
    }

    if (amounts.isEmpty) return null;
    if (amounts.length >= 2) {
      var best = amounts.reduce((a, b) => a > b ? a : b);
      for (final a in amounts) {
        final inferred = _inferLogiGrossFareFromPlatformFee(a);
        if (inferred != null && inferred > best) best = inferred;
      }
      return best;
    }

    final only = amounts.first;
    return _inferLogiGrossFareFromPlatformFee(only) ?? only;
  }

  static int _parseFare(
    List<String> lines, {
    List<TextBlock>? blocks,
    String? fullText,
    bool colmanner = false,
  }) {
    if (!colmanner) {
      final fromStack = _grossFareFromLogiFareDepositStack(lines);
      if (fromStack != null && fromStack >= 1000) return fromStack;

      int maxFare = 0;
      for (final line in lines) {
        final v = _strictFareDigitsFromLine(line);
        if (v != null && v >= 1000 && v <= 999999) {
          if (v > maxFare) maxFare = v;
        }
      }
      if (maxFare > 0) {
        final inferred = _inferLogiGrossFareFromPlatformFee(maxFare);
        if (inferred != null &&
            inferred > maxFare &&
            _indexOfLabel(lines, '입금액') >= 0) {
          return inferred;
        }
        return maxFare;
      }
    }
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
    if (line.contains('법인명') || line.contains('할증요금') || line.contains('할증') || n == '적요') return true;
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
      final isJeoyoOrMemo = nk.startsWith('적요') || nk.startsWith('메모') || nk.startsWith('고객');
      final hasWaypointKeyword = nk.contains('경유');
      if (!isJeoyoOrMemo && !hasWaypointKeyword) continue;
      if (nk.startsWith('고객과의거리') || nk.startsWith('고객위치') || nk.startsWith('고객정보') || nk.startsWith('고객과')) continue;
      final joined = lines.sublist(i, (i + 5 > lines.length) ? lines.length : i + 5).join(' ');
      if (joined.contains('대기,경유') ||
          joined.contains('경유 발생시') ||
          joined.contains('경유발생시') ||
          joined.contains('경유변동시') ||
          joined.contains('경유 변동시') ||
          joined.contains('경유시 상황실')) {
        continue;
      }
      final w = RegExp(r'경유\s*[:：]?\s*([^\n\]/}\]]+?)(?:\s*[/\]}]|$)', caseSensitive: false).firstMatch(joined);
      if (w != null) {
        var wp = w.group(1)!.trim();
        if (wp.contains('고객과의')) {
          wp = wp.split('고객과의').first.trim();
        }
        // 모수서울 케이스 (747 -> 그47 오인식 보정)
        wp = wp.replaceAllMapped(RegExp(r'([그기])(\d{2,})'), (m) => '7${m.group(2)}');
        if (wp.contains(')')) {
          wp = wp.split(')').first.trim();
        }
        return wp;
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

  /// 뭉친 OCR 한 줄에서 출발/도착을 분할한다. [isLogi]==true 이면 로지(상세: head+tail), false 이면 콜마너(상세: tail 우선).
  static ({String start, String end}) _splitAddressText(String rawText, {required bool isLogi}) {
    var joined = rawText.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    // 뭉개진 지명(예: 역삼동서울) 사이에 강제로 공백을 주입하여 후속 정규식이 작동하게 함
    joined = _injectSpaceBeforeProvinceToken(joined);

    var splitIdx = -1;
    var label = '';

    // 1단계: 명시적 라벨 탐색 (도착지, 착지)
    final labelMatch = RegExp(r'(^|\s)(도\s*착\s*지?|착\s*지)').firstMatch(joined);
    if (labelMatch != null) {
      splitIdx = labelMatch.start;
      label = labelMatch.group(0)!;
    }

    // 2단계: 라벨 누락 시 '주소 종결어 + 광역지명' 패턴으로 정밀 분할 (상호명 무관하게 100% 보존)
    if (splitIdx == -1) {
      // 패턴: 출발지의 끝부분(동/읍/면/리/로/길/번지/층/호/지하 또는 번지숫자) 뒤에 공백이 있고, 도착지의 시작부분(광역지명)이 오는 경계 탐색
      final boundaryRx = RegExp(
        r'([가-힣\d]+(?:동|읍|면|리|로|길|번지|층|호|지하|\d+(?:-\d+)?)\s*(?:[A-Za-z\d@ⓞ]+)?(?:스타)?)\s+(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)\s',
      );
      final boundaryMatch = boundaryRx.firstMatch(joined);

      if (boundaryMatch != null) {
        // 출발지가 끝나는 지점과 도착지가 시작되는 지점 사이(공백)에서 정확히 자름
        splitIdx = boundaryMatch.end - boundaryMatch.group(2)!.length - 1;
      } else {
        // 3단계 폴백: 기존 광역지명 2번째 출현 위치 탐색
        final regionRx = RegExp(r'(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)');
        final matches = regionRx.allMatches(joined).toList();
        if (matches.length >= 2) {
          for (var i = 1; i < matches.length; i++) {
            // 로지콜 '상세:' 내부의 지명은 무시 (경유지나 상세주소 내의 광역지명 오인식 방어)
            final textBefore = joined.substring(0, matches[i].start);
            if (textBefore.contains('상세:') &&
                !textBefore.contains(RegExp(r'(동|읍|면|리|로|길)'))) {
              continue;
            }

            if (matches[i].start > 8) {
              // 상호명이 짤리는 현상 방지
              splitIdx = matches[i].start;
              break;
            }
          }
        }
      }
    }

    // 분할 적용 및 텍스트 정제
    if (splitIdx != -1) {
      var s = joined.substring(0, splitIdx).trim();
      var e = joined.substring(splitIdx).trim();
      if (label.isNotEmpty) {
        e = e.replaceFirst(label, '').trim();
      }

      s = s.replaceFirst(RegExp(r'^\s*출발지?\s*'), '').replaceAll(RegExp(r'\s*(출발지|도착지|지도)\s*'), ' ').trim();
      e = e.replaceFirst(RegExp(r'^\s*도\s*착\s*지?\s*'), '').replaceAll(RegExp(r'\s*(출발지|도착지|지도)\s*'), ' ').trim();

      return (
        start: _cleanAddr(s, isLogi: isLogi, isStart: true),
        end: _cleanAddr(e, isLogi: isLogi, isStart: false),
      );
    }

    return (
      start: _cleanAddr(joined, isLogi: isLogi, isStart: true),
      end: '',
    );
  }

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

  static String _cleanAddr(String s, {required bool isLogi, required bool isStart}) {
    var res = s.trim();
    if (res.isEmpty) return '';

    // Exclude noise like "동 n후", "n후", "n후)"
    res = res.replaceFirst(RegExp(r'^[가-힣\s]*n후\)?\s*'), '');

    // 적요/메모란에 딸려온 괄호 패턴 전체 삭제 (예: [자택:...], {후불50K], 등)
    res = res.replaceAll(RegExp(r'\[.*?\]'), ' ');
    res = res.replaceAll(RegExp(r'\{.*?\]'), ' ');
    res = res.replaceAll(RegExp(r'\{.*?\}'), ' ');

    // 인천송도동+푸르지오… → 인천 송도동 푸르지오…
    res = res.replaceAllMapped(
      RegExp(
        r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)([가-힣])',
      ),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    res = res.replaceAll('+', ' ');

    // 1. 콜마너/로지 공통 악성 노이즈 철벽 제거 (하단 UI 버튼 등 모든 시스템 문구)
    res = res.replaceAll(RegExp(r'[Q|/\\{}]'), ' ');
    res = res.replaceAll(
      RegExp(
        r'\(?(고객전화|상황실연락처|상황실|지사명|고객명|고객ID|오더번호|차량번호|전화2|전화|메모|출도|경로거리|배정취소|맞춤콜|잔여시간|도착알림|취소불가|출발지에도착|완료처리|완료|배차취소|배차|경로안내|안내|갱신|닫기|처리|취소|출발지지도|지도|출발지 도착 연기|출발지 도착|서명|고객위치|출도경로|길안내|도착 알림|운행 시작|운행시작연기|후불|제휴|즉후|카드|천사|정장)\)?',
      ),
      ' ',
    );
    res = res.replaceAll(RegExp(r'[a-zA-Z0-9가-힣\s]*이니~'), ' ');
    res = res.replaceAll(RegExp(r'\d+분\s*\d+초\s*남음'), ' ');
    res = res.replaceAll(RegExp(r'\d+분\s*\d+초'), ' ');

    // 2. OCR 오인식 글자 및 층수/지하 보정 (데이터 축적 기반)
    res = res.replaceAllMapped(RegExp(r'([가-힣\s])[그기](\d)'), (m) => '${m.group(1)}7${m.group(2)}');
    res = res.replaceAllMapped(RegExp(r'([가-힣\s])나(\d)'), (m) => '${m.group(1)}4${m.group(2)}');
    res = res.replaceAll(RegExp(r'지핟|지합'), '지하');
    res = res.replaceAllMapped(RegExp(r'([0-9B])총'), (m) => '${m.group(1)}층');
    res = res.replaceAll(RegExp(r'B!|B\|'), 'B1');
    res = res.replaceAllMapped(RegExp(r'기-(\d+)'), (m) => '7-${m.group(1)}');

    // 3. 라벨 잔해물 제거
    res = res.replaceAll(RegExp(r'^(출발지|도착지|위치|경유지)\s*', caseSensitive: false), '');
    res = res.replaceAll(RegExp(r'\s+(출발지|도착지|지도|서명|길안내|고객위치|고객과의\s*거리\s*[:：]?\s*.*)$', caseSensitive: false), '');
    res = res.replaceAll(RegExp(r'출\s*도\s*경로거리.*$', caseSensitive: false), '');
    res = res.replaceAll(RegExp(r'경로거리\s*[:：]?\s*[a-zA-Z0-9\.]+(?:km)?', caseSensitive: false), '');
    res = res.replaceAll(RegExp(r'경로거리\s*[:：]?\s*[^\s]+'), '');
    res = res.replaceAll(RegExp(r'킥보드\s*[xX]\)?', caseSensitive: false), ' ');

    // 4. 로지 '상세:' 처리 — 출발은 **상세: 뒤 행정주소**만(상호·경로 제외)
    if (res.contains('상세:')) {
      if (isLogi && isStart) {
        res = res.split(RegExp(r'상세\s*:', caseSensitive: false)).last.trim();
      } else if (isLogi) {
        res = _joinHeadAndTailAfterFirstSangse(res);
      } else {
        res = res.split(RegExp(r'상세\s*:', caseSensitive: false)).last.trim();
      }
    }

    // 상세 꼬리 중복 (예: 서린동 99-0 서린동 99)
    res = res.replaceAllMapped(
      RegExp(r'([가-힣]+동\s+\d+-\d+)\s+[가-힣]+동\s+\d+\s*$'),
      (m) => m.group(1)!,
    );

    res = res.replaceAll(RegExp(r'\s+주차$'), '');

    if (!isLogi && !isStart) {
      res = res.replaceFirst(RegExp(r'/\s*0\s*$'), '').trim();
    }

    // 5. 어절 및 단어 중복 지명 제거
    res = res.replaceAllMapped(
      RegExp(r'\b([가-힣\s]+?[동읍면리구시군시구])\s*\)?\s*\1\b'),
      (m) => m.group(1)!,
    );
    res = res.replaceAllMapped(RegExp(r'([가-힣]+[동읍면리구시군])\s*\)?\s*\1'), (m) => m.group(1)!);

    // 6. 주소 끝자리 순수 오더 번호 및 영문/숫자 노이즈 제거
    res = res.replaceAll(RegExp(r'(?<!\()\b\d{6,}\b(?!\))'), ' ');
    res = res.replaceAll(RegExp(r'\b[a-zA-Z\d.]{2,8}\b\s*$'), ' ');

    // 7. 카카오 매칭률/UI 노이즈 잔해 제거
    res = res.replaceAll(RegExp(r'\b\d{1,3}\s*[lI|%]\s*(?:\(\d{1,2}\))?\b', caseSensitive: false), ' ');
    res = res.replaceAll(RegExp(r'\b[oO]\s*\.?\s*[lI|%]\s*\d+\b', caseSensitive: false), ' ');
    res = res.replaceAll(RegExp(r'\b\d{1,3}\s*[lI|%]\s*\d+\b', caseSensitive: false), ' ');

    // 8. 결제 수단 약어 제거 (예: "카", "현", "후", "즉")
    res = res.replaceAll(RegExp(r'(^|\s)[\x22\x27“‘]?([카현후즉])[\x22\x27”’]?(?=\s|$)'), ' ');

    res = res.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _deduplicateAdjacentTokens(res);
  }

  /// 로지: 출발지·고객·적요 이후 한 덩어리 → [_splitAddressText].
  static ({String start, String end, String joined}) _parseLogiLocations(List<String> lines) {
    final buffer = <String>[];
    var inBlock = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final n = _normalizeKey(line);
      if (!inBlock && (n.startsWith('출발지') || RegExp(r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)').hasMatch(line))) {
        inBlock = true;
      }
      if (!inBlock) continue;

      if (_isLogiAddressBlockFooterLine(line) ||
          _isLogiStopLine(line) ||
          _isCustomerMetaLine(line) ||
          line.contains('도도착완료')) {
        break;
      }
      if (_isOrphanCustomerNumber(line)) continue;
      if (n == '출발지' || n == '도착지' || n == '지도') {
        buffer.add(line);
        continue;
      }
      if (_isLogiNoiseLine(line) && !line.contains('상세:')) continue;
      if (_isLogiPickupArrivalStatusBanner(line)) continue;
      if (_isLogiMemoLineForBody(line) && !line.contains('상세:')) continue;
      if (_isLogiFareClassNoiseLine(line) || _isLogiCountdownRemainLine(line)) continue;
      if (_isLogiUiNoiseLine(line)) continue;
      buffer.add(line);
    }
    final joined = buffer.join(' ');
    final split = _splitAddressText(joined, isLogi: true);
    return (start: split.start, end: split.end, joined: joined);
  }

  /// 콜마너: 지사명·고객명·위치·출발지 이후 블록 + 경유지 라인에서 waypoint.
  static ({String start, String end, String waypoint, String joined}) _parseColmannerLocations(List<String> lines) {
    final buffer = <String>[];
    var waypoint = '';
    var inBlock = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final n = _normalizeKey(line);
      final noSpace = line.replaceAll(RegExp(r'\s+'), '');

      if (noSpace.contains('경유지')) {
        waypoint = line.split(RegExp(r'경\s*유\s*지', caseSensitive: false)).last.replaceAll(RegExp(r'[:：]'), '').trim();
        waypoint = waypoint.split(')').first.trim();
        break;
      }

      if (!inBlock) {
        if (n.startsWith('출발지')) {
          inBlock = true;
        } else if ((n.startsWith('지사명') || n.startsWith('고객명') || n.startsWith('위치')) && i + 1 < lines.length) {
          inBlock = true;
          continue;
        } else if (RegExp(r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)').hasMatch(line)) {
          inBlock = true;
        }
      }
      if (!inBlock) continue;

      if (noSpace.contains('요금') ||
          noSpace.contains('현금')) {
        break;
      }
      if (RegExp(
        r'^(출도|적요|지도|고객위치|길안내|서명|갱신|닫기)$',
        caseSensitive: false,
      ).hasMatch(noSpace)) {
        continue;
      }
      if (n.startsWith('적요')) continue;
      if (n.startsWith('지사명') || n.startsWith('고객명')) continue;

      final startsWithMetro = RegExp(
        r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)',
      ).hasMatch(line);

      if (n.startsWith('출발지') || n.startsWith('도착지') || n.startsWith('위치') || startsWithMetro) {
        // primary address line - never skip
      } else {
        if (_isColmannerNoiseLine(line) || _isColmannerMemoLine(line)) continue;
        if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
      }
      buffer.add(line);
    }
    final joined = buffer.join(' ');
    final cleanedJoined = joined.replaceAll(RegExp(r'^(?:출발지|도착지|출도|적요|지도|고객정보|고객전화|연락처|상황실|TALK|입금합계|차감합계|고객명|지사명|위치|\s)+', caseSensitive: false), '').trim();
    final split = _splitAddressText(cleanedJoined.isEmpty ? joined : cleanedJoined, isLogi: false);
    return (start: split.start, end: split.end, waypoint: waypoint, joined: joined);
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

  /// 메뉴 상단에 잠깐 보이는 도착 미리보기(예: `송도동)신림역/`) — 실제 도착지가 아니다.
  static bool _isLogiSpuriousDestPreviewLine(String text) {
    final t = text.replaceAll(' ', '');
    if (t.contains('신림역') && !RegExp(r'단지|아파트|푸르지오|\+|@').hasMatch(t)) {
      return true;
    }
    if (RegExp(r'송도동\)?신림역').hasMatch(t)) return true;
    return false;
  }

  /// 하단 UI 이후 실제 도착 주소 블록(단지명·`+` 결합 등).
  static bool _looksLikeLogiFinalDestinationGroup(String text) {
    if (text.contains('상세:')) return false;
    if (_isLogiSpuriousDestPreviewLine(text)) return false;
    if (RegExp(r'\+|단지|아파트|푸르지오|빌딩|타운|월드마크|@').hasMatch(text)) {
      return true;
    }
    final compact = text.replaceAll(' ', '');
    if (RegExp(r'인천.*송도').hasMatch(compact) && compact.length >= 8) {
      return true;
    }
    return false;
  }

  static int? _indexOfLogiSangseGroup(List<List<String>> groups) {
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].join(' ').contains('상세:')) return i;
    }
    return null;
  }

  static int _indexOfLogiFinalDestinationGroup(
    List<List<String>> groups, {
    int? afterIndex,
  }) {
    var pick = -1;
    for (var i = 0; i < groups.length; i++) {
      if (afterIndex != null && i <= afterIndex) continue;
      final joined = groups[i].join(' ');
      if (_looksLikeLogiFinalDestinationGroup(joined)) pick = i;
    }
    if (pick >= 0) return pick;
    for (var i = groups.length - 1; i >= 0; i--) {
      if (afterIndex != null && i <= afterIndex) continue;
      final joined = groups[i].join(' ');
      if (!_isLogiSpuriousDestPreviewLine(joined) && !joined.contains('상세:')) {
        return i;
      }
    }
    return groups.length - 1;
  }

  static bool _logiMergedHasFinalDestination(List<List<String>> groups) {
    for (final g in groups) {
      if (_looksLikeLogiFinalDestinationGroup(g.join(' '))) return true;
    }
    return false;
  }

  static ({String start, String end}) _resolveLogiLocationTextsFromGroups(
    List<List<String>> groups,
  ) {
    if (groups.isEmpty) return (start: '', end: '');
    if (groups.length == 1) {
      return (
        start: _cleanAddr(groups[0].join(' '), isLogi: true, isStart: true),
        end: '',
      );
    }

    final sangseIdx = _indexOfLogiSangseGroup(groups);
    if (sangseIdx != null) {
      final startText = groups[sangseIdx].join(' ');
      final endIdx = _indexOfLogiFinalDestinationGroup(groups, afterIndex: sangseIdx);
      final endText = groups[endIdx].join(' ');
      return (
        start: _cleanAddr(startText, isLogi: true, isStart: true),
        end: _cleanAddr(endText, isLogi: true, isStart: false),
      );
    }

    var startText = groups[0].join(' ');
    var endText = groups[1].join(' ');
    if (!startText.contains('상세:') && endText.contains('상세:')) {
      startText = groups[1].join(' ');
      endText = groups[0].join(' ');
    }
    if (groups.length >= 3) {
      final endIdx = _indexOfLogiFinalDestinationGroup(groups);
      endText = groups[endIdx].join(' ');
    }
    return (
      start: _cleanAddr(startText, isLogi: true, isStart: true),
      end: _cleanAddr(endText, isLogi: true, isStart: false),
    );
  }

  static ({String start, String end}) _parseLogiLocationsMerged(List<String> lines) {
    final groups = <List<String>>[];
    List<String> currentGroup = [];

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;

      final n = _normalizeKey(t);
      final startsWithMetro = RegExp(
        r'^(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)',
      ).hasMatch(t);

      if (n.startsWith('출발지') || n.startsWith('도착지') || n.startsWith('위치') || startsWithMetro) {
        // primary address line - never skip
      } else {
        if (_isLogiUiNoiseLine(t) ||
            _isLogiNoiseLine(t) ||
            _isCustomerMetaLine(t) ||
            _isOrphanCustomerNumber(t) ||
            _isLogiPickupArrivalStatusBanner(t) ||
            _isLogiSkippableAddressRelabelLine(t) ||
            _isLogiMemoLineForBody(t) ||
            _isLogiFareClassNoiseLine(t) ||
            _isLogiCountdownRemainLine(t)) {
          continue;
        }
      }

      if (_isLogiAddressBlockFooterLine(t)) {
        final nk = _normalizeKey(t);
        if (nk == '완료' ||
            nk == '처리' ||
            nk == '서명' ||
            nk == '닫기' ||
            nk == '배차') {
          if (_logiMergedHasFinalDestination(groups) &&
              (currentGroup.isEmpty || groups.isNotEmpty)) {
            break;
          }
        }
        continue;
      }

      if (RegExp(r'^0\d{1,2}-\d{3,4}-\d{4}$').hasMatch(t)) continue;

      final hasMetro = _leadingMetroProvinceToken(t) != null ||
          RegExp(r'(서울|경기|인천|강원|충남|충북|대전|경북|경남|대구|부산|울산|전남|전북|광주|제주|세종)').hasMatch(t);
      final isSangse = t.contains('상세:');

      if (hasMetro || isSangse) {
        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
        }
        currentGroup = [t];
      } else if (currentGroup.isNotEmpty) {
        if (t.length >= 2) {
          currentGroup.add(t);
        }
      }
    }
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    return _resolveLogiLocationTextsFromGroups(groups);
  }

  static ({String start, String end, String waypoint}) _parseColmannerLocationsMerged(List<String> lines) {
    final c = _parseColmannerLocations(lines);

    final startIdx = _indexOfLabel(lines, '출발지');
    final endIdx = _indexOfLabel(lines, '도착지');
    if (startIdx >= 0 && endIdx == startIdx + 1) {
      var sRem = _labelRemainder(lines[startIdx], '출발지').trim();
      var eRem = _labelRemainder(lines[endIdx], '도착지').trim();
      final cleanRe = RegExp(r'[()\[\]\{\}\s]*(?:후불|카드|현금|즉후|정장|제휴|천사)[\s)]*');
      sRem = sRem.replaceAll(cleanRe, '').trim();
      eRem = eRem.replaceAll(cleanRe, '').trim();
      if (sRem.isEmpty && eRem.isEmpty) {
        // Consecutive empty headers - let's fall through to the merged block parser (c).
      } else {
        final leg = _parseColmannerLocationsLegacy(lines);
        return (start: leg.start, end: leg.end, waypoint: c.waypoint);
      }
    }
    if (_colmannerHasAnchorBetweenStartEndLabels(lines)) {
      final leg = _parseColmannerLocationsLegacy(lines);
      return (start: leg.start, end: leg.end, waypoint: c.waypoint);
    }

    if (c.joined.trim().isNotEmpty) {
      final flatKey = c.joined.replaceAll(RegExp(r'\s'), '');
      final hasDestLabel = flatKey.contains('도착지');
      if (!(c.end.isEmpty && hasDestLabel) && !(c.start.isEmpty && c.end.isEmpty)) {
        final adjusted = _colmannerAdjustDoubleMetroInDeparture(c.start, c.end);
        return (start: adjusted.start, end: adjusted.end, waypoint: c.waypoint);
      }
    }

    if (startIdx < 0 || endIdx < 0 || startIdx >= endIdx) {
      final startChunk = _extractChunk(
        lines,
        startKeys: const ['출발지'],
        endKeys: const ['도착지'],
        hardStopKeys: _colmannerEndStops,
      );
      final endChunk = _resolveColmannerEndChunk(lines);
      return (start: startChunk, end: endChunk, waypoint: c.waypoint);
    }

    final leg = _parseColmannerLocationsLegacy(lines);
    return (start: leg.start, end: leg.end, waypoint: c.waypoint);
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

  static bool _isPurePaymentOrMemoLine(String line) {
    var s = line.replaceAll(RegExp(r'[()\[\]\{\}\s]'), '');
    s = s.replaceAll(RegExp(r'(?:후불|카드|현금|즉후|정장|제휴|천사|요금|결재|결제)'), '');
    if (s.isEmpty) return true;
    s = s.replaceAll(RegExp(r'\d+(?:분|시간|[kK]|[oO][kK]|원)?'), '');
    s = s.replaceAll(RegExp(r'[,\./\-~X]'), '');
    s = s.replaceAll(RegExp(r'(?:완료|입금|킥|활|대기|경유|발생|시|후)'), '');
    return s.trim().isEmpty;
  }

  static bool _isColmannerMemoLine(String line) {
    final n = _normalizeKey(line);
    if (n.startsWith('출도') || n.startsWith('적요')) return true;
    if (line.contains('경로거리')) return true;
    if (_isPurePaymentOrMemoLine(line)) return true;
    if (line.startsWith('(예상')) return true;
    if (line.contains('자택') || line.contains('[자택]') || line.contains('자택:')) return true;
    if (line.contains('차량') || line.contains('[차량]') || line.contains('차량:')) return true;
    if (line.contains('법]') || line.contains('정장]')) return true;
    if (line.contains('기사님') || line.contains('[주차]')) return true;
    if (line.contains('비흡연') || line.contains('킥보드') || line.contains('휠X')) return true;
    if (RegExp(r'\(\d+-\d+\)').hasMatch(line)) return true;
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
    '요금',
    '현금',
    '적요',
    '고객정보',
    '고객위치',
  ];

  static bool _isColmannerStopLine(String line) {
    var n = _normalizeKey(line);
    // 괄호 '(' 나 ')' 가 처음에 오면 제거하여 매칭 감지
    n = n.replaceFirst(RegExp(r'^[\(\)\{\}\[\]\s]+'), '');
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
    if (line.contains('고객전화') || line.contains('상황실') || line.contains('상황실연락처')) return true;
    if (line.contains('이니~') || line.contains('이니--') || line.contains('이니-니')) return true;
    if (n.contains('차감합계') || n.contains('입금합계') || n.contains('경로거리') || n.contains('소요시간') || n.contains('출도')) return true;
    if (n.contains('기사님')) return true;
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
      if (_isColmannerNoiseLine(line) || _isColmannerMemoLine(line)) continue;
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
    return line.length >= 4 && RegExp(r'[가-힣]').hasMatch(line) && !line.contains('운행');
  }

  static String _normalizeAddressChunk(String chunk) {
    var s = chunk.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'[()\[\]\{\}\s]*(?:후불|카드|현금|즉후|정장|제휴|천사)[\s)]*'), ' ');
    s = s.replaceFirst(RegExp(r'\s+\d+-\d+\s*$'), '');
    s = s.replaceAll(RegExp(r'\s+\d+(?:[kK]|[oO][kK])\s*\]?\s*.*$'), '');
    s = s.replaceAll(RegExp(r'\s*(?:완료|입금|결재|결제|킥|활|휠|비흡연|킥보드|자택|차량|기사님).*$'), '');
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


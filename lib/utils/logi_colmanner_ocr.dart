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
    final fare = _parseFare(lines, fullText: fullText, blocks: blocks);

    final locations = _parseLogiLocations(lines);
    final start = _normalizeAddressChunk(locations.start);
    final end = _normalizeAddressChunk(locations.end);
    const waypoint = '';

    return PartnerCallParsed(
      driveTimeHm: time,
      grossFare: fare,
      startLocation: start,
      endLocation: end,
      waypoint: waypoint,
    );
  }

  static PartnerCallParsed parseColmanner(String fullText, {List<TextBlock>? blocks}) {
    final lines = _lines(fullText);
    final time = _parseTime(lines, blocks: blocks);
    final fare = _parseFare(lines, fullText: fullText, blocks: blocks);

    final locations = _parseColmannerLocations(lines);
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
        if (block.boundingBox.top >= 250) break;
        final m = RegExp(r'(\d{1,2})[:：\.](\d{1,2})').firstMatch(block.text);
        if (m != null) {
          final raw = '${m.group(1)}:${m.group(2)}';
          return normalizeDriveTimeHm(raw) ?? raw;
        }
      }
    }

    for (final l in lines.take(8)) {
      final m = RegExp(r'(\d{1,2})[:：\.](\d{1,2})').firstMatch(l);
      if (m != null) {
        final raw = '${m.group(1)}:${m.group(2)}';
        return normalizeDriveTimeHm(raw) ?? raw;
      }
    }
    return '';
  }

  static int _parseFare(
    List<String> lines, {
    String? fullText,
    List<TextBlock>? blocks,
  }) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.contains('요금')) continue;

      final m = RegExp(r'요금[^\d]{0,12}([\d,]{4,7})\s*원?').firstMatch(l);
      if (m != null) {
        final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v > 0) return v;
      }

      final fromLine = parseLogiFareFromOcrText(l);
      if (fromLine != null) return fromLine;

      for (var j = i + 1; j < lines.length && j <= i + 25; j++) {
        final trimmed = lines[j].trim();
        if (_isLogiCountdownRemainLine(trimmed) || _isLogiFareClassNoiseLine(trimmed)) continue;
        if (RegExp(r'\d{9,}').hasMatch(trimmed)) continue;
        final fromNext = parseLogiFareFromOcrText(lines[j]);
        if (fromNext != null && fromNext >= 1000 && fromNext <= 999_999) return fromNext;
        final n = RegExp(r'^([\d,]{4,7})\s*[!원]*$').firstMatch(trimmed);
        if (n != null) {
          final v = int.tryParse((n.group(1) ?? '').replaceAll(',', ''));
          if (v != null && v > 0) return v;
        }
      }
    }

    if (blocks != null && blocks.isNotEmpty) {
      final sorted = List<TextBlock>.from(blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      for (var i = 0; i < sorted.length; i++) {
        if (!sorted[i].text.contains('요금')) continue;
        int? fare = parseLogiFareFromOcrText(sorted[i].text);
        for (final j in [i - 1, i + 1]) {
          if (fare == null && j >= 0 && j < sorted.length) {
            fare = parseLogiFareFromOcrText(sorted[j].text);
          }
        }
        if (fare != null) return fare;
      }
    }

    if (fullText != null && fullText.isNotEmpty) {
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('요금')) continue;
        final window = <String>[];
        for (var j = i; j <= i + 25 && j < lines.length; j++) {
          window.add(lines[j]);
        }
        final fare = parseLogiFareFromOcrText(window.join('\n'));
        if (fare != null) return fare;
      }
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

  static bool _hasSubstantiveColmannerStart(String startLead) {
    if (startLead.isEmpty) return false;
    if (_looksRegionLike(startLead) || _looksLikeDestinationLead(startLead)) return true;
    return startLead.length >= 6;
  }

  static bool _isColmannerAnchorLine(String line) {
    final n = _normalizeKey(line);
    return n == '출도' || n == '적요';
  }

  static bool _isLogiDestinationLead(String line) {
    if (_looksLikeDestinationLead(line)) return true;
    if (line.contains(')')) return true;
    return RegExp(r'[가-힣]+동\)?').hasMatch(line);
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
        .replaceAll(RegExp(r'경로거리\s*[:：]\s*[^\s)]+'), '')
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
    var destStart = body.length;
    for (var i = 1; i < body.length; i++) {
      if (_isLogiDestinationLead(body[i])) {
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

  static ({String start, String end}) _parseLogiLocations(List<String> lines) {
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
      if (_isLogiUiNoiseLine(line)) break;
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
        if (_isLogiUiNoiseLine(line)) {
          if (_normalizeKey(line) == '지도') continue;
          break;
        }
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
    var cleanedStart = _stripLogiUiTokens(_normalizeAddressChunk(start));
    var cleanedEnd = _stripLogiUiTokens(_normalizeAddressChunk(end));
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

  static ({String start, String end}) _parseColmannerLocations(List<String> lines) {
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
      if (_isColmannerStopLine(line)) {
        // "출도" 단독 줄은 주소 블록 앞에 붙는 UI 구분선이라, 그 다음 줄의 출발·도착 텍스트를 잃지 않도록 건너뛴다.
        if (_normalizeKey(line) == '출도') continue;
        break;
      }
      if (_isCustomerMetaLine(line) || _isOrphanCustomerNumber(line)) continue;
      if (_isColmannerNoiseLine(line)) continue;
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


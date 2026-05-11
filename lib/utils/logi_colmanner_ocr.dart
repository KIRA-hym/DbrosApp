import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'drive_time_format.dart';

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
    final time = _parseTime(lines);
    final fare = _parseFare(lines);

    final startChunk = _extractChunk(
      lines,
      startKeys: const ['출발지'],
      endKeys: const ['도착지'],
      hardStopKeys: const ['고객id', '오더번호', '차량번호', '전화2', '전화', '고객과의 거리', '적요'],
    );
    final endChunk = _extractChunk(
      lines,
      startKeys: const ['도착지'],
      endKeys: const ['고객id', '오더번호', '차량번호', '전화2', '전화', '고객과의 거리', '적요'],
      hardStopKeys: const ['고객id', '오더번호', '차량번호', '전화2', '전화', '고객과의 거리', '적요'],
    );

    final start = _normalizeAddressChunk(startChunk, keepDetailPrefix: true);
    final end = _normalizeAddressChunk(endChunk, keepDetailPrefix: false);
    final waypoint = _parseWaypoint(lines);

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
    final time = _parseTime(lines);
    final fare = _parseFare(lines);

    final startChunk = _extractChunk(
      lines,
      startKeys: const ['출발지'],
      endKeys: const ['도착지'],
      hardStopKeys: const ['출도', '요금', '현금', '입금합계', '차감합계', '적요', '고객정보', '고객위치'],
    );
    final endChunk = _extractChunk(
      lines,
      startKeys: const ['도착지'],
      endKeys: const ['경유지', '출도', '요금', '현금', '입금합계', '차감합계', '적요', '고객정보', '고객위치'],
      hardStopKeys: const ['경유지', '출도', '요금', '현금', '입금합계', '차감합계', '적요', '고객정보', '고객위치'],
    );

    final start = _normalizeAddressChunk(startChunk, keepDetailPrefix: true);
    final end = _normalizeAddressChunk(endChunk, keepDetailPrefix: false);
    final waypoint = _parseWaypoint(lines);

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

  static String _parseTime(List<String> lines) {
    for (final l in lines.take(8)) {
      final m = RegExp(r'(\d{1,2})[:：\.](\d{1,2})').firstMatch(l);
      if (m != null) {
        final raw = '${m.group(1)}:${m.group(2)}';
        return normalizeDriveTimeHm(raw) ?? raw;
      }
    }
    return '';
  }

  static int _parseFare(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.contains('요금')) continue;
      final m = RegExp(r'요금[^\d]{0,12}([\d,]{4,7})\s*원?').firstMatch(l);
      if (m != null) {
        final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v > 0) return v;
      }
      // "요금" 다음 줄에 금액이 떨어진 경우
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final n = RegExp(r'^([\d,]{4,7})\s*원?$').firstMatch(lines[j].trim());
        if (n != null) {
          final v = int.tryParse((n.group(1) ?? '').replaceAll(',', ''));
          if (v != null && v > 0) return v;
        }
      }
    }
    return 0;
  }

  static String _extractChunk(
    List<String> lines, {
    required List<String> startKeys,
    required List<String> endKeys,
    required List<String> hardStopKeys,
  }) {
    final starts = startKeys.map(_normalizeKey).toList();
    final ends = endKeys.map(_normalizeKey).toList();
    final stops = hardStopKeys.map(_normalizeKey).toList();

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
    final firstLine = lines[idx];
    final startKey = startKeys.first;
    final firstRemainder = firstLine.replaceFirst(RegExp('^\\s*$startKey\\s*'), '').trim();
    if (firstRemainder.isNotEmpty) buffer.add(firstRemainder);

    for (var i = idx + 1; i < lines.length; i++) {
      final n = _normalizeKey(lines[i]);
      if (ends.any((k) => n.startsWith(k))) break;
      if (stops.any((k) => n.startsWith(k))) break;
      if (n.startsWith('지사명') || n.startsWith('고객명')) break;
      buffer.add(lines[i]);
    }

    return buffer.join(' ').trim();
  }

  static String _normalizeAddressChunk(String chunk, {required bool keepDetailPrefix}) {
    var s = chunk.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!keepDetailPrefix) {
      s = s.replaceAll(RegExp(r'\b상세\s*:\s*'), '');
    }
    return s.trim();
  }

  static String _parseWaypoint(List<String> lines) {
    for (final line in lines) {
      if (line.contains('경유지')) {
        final rest = line.replaceFirst(RegExp(r'^.*경유지\s*'), '').trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    for (final line in lines) {
      if (!line.contains('경유')) continue;
      final m = RegExp(r'경유\s*[:：]?\s*([^\}\]]+)').firstMatch(line);
      if (m != null) {
        final w = m.group(1)?.trim() ?? '';
        if (w.isNotEmpty) return w;
      }
    }
    return '';
  }
}


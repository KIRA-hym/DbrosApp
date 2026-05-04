import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'drive_time_format.dart';

/// T맵 대리 「운행 상세 정보」 파싱 결과
class TmapTripDetailParsed {
  TmapTripDetailParsed({
    required this.driveDateYmd,
    required this.driveStartTimeHm,
    required this.grossFare,
    required this.startAddress,
    required this.endAddress,
  });

  final String driveDateYmd;
  final String driveStartTimeHm;
  final int grossFare;
  final String startAddress;
  final String endAddress;
}

/// T맵 대리 「운행 상세 정보」 스크린 OCR.
/// 예: `2026.5.2 (토) 01:51 ~ 02:24`, 출발/도착 라벨 다음 줄, `실수익 28,800P`
class TmapTripDetailOcr {
  TmapTripDetailOcr._();

  /// 「운행 상세 정보」 타이틀 또는 티맵 대리 영수증 패턴
  static bool isTripDetailScreen(String fullText) {
    final c = fullText.replaceAll(RegExp(r'\s'), '');
    if (c.contains('운행상세정보')) return true;
    if (fullText.contains('TMAP대리') ||
        fullText.contains('TMAP') ||
        fullText.contains('티맵')) {
      if (fullText.contains('실수익') || fullText.contains('운행일자')) return true;
    }
    if (fullText.contains('출발') &&
        fullText.contains('도착') &&
        fullText.contains('실수익') &&
        fullText.contains('운행일자')) {
      return true;
    }
    return false;
  }

  /// [fullText]: ML Kit `RecognizedText.text`, [blocks]: 라벨·값 세로 분리 보조
  static TmapTripDetailParsed? tryParse(String fullText, {List<TextBlock>? blocks}) {
    if (!isTripDetailScreen(fullText)) return null;

    String driveDateYmd = '';
    String driveStartTimeHm = '';
    int grossFare = 0;
    String startAddress = '';
    String endAddress = '';

    final normalized = fullText.replaceAll('\r', '\n');

    final trip = RegExp(
      r'(\d{4})\.(\d{1,2})\.(\d{1,2})\s*\([^)]*\)\s*(\d{1,2}:\d{2})\s*~\s*(\d{1,2}:\d{2})',
    ).firstMatch(normalized);
    if (trip != null) {
      final y = int.parse(trip.group(1)!);
      final mo = int.parse(trip.group(2)!);
      final d = int.parse(trip.group(3)!);
      driveDateYmd = DateFormat('yyyy-MM-dd').format(DateTime(y, mo, d));
      final rawStart = trip.group(4)!;
      driveStartTimeHm = normalizeDriveTimeHm(rawStart) ?? rawStart;
    }

    final flatForFare = normalized.replaceAll(RegExp(r'\s+'), ' ');
    final fareMatch = RegExp(
      r'실수익\s*[:\s]*([\d,]+)\s*P',
      caseSensitive: false,
    ).firstMatch(flatForFare);
    if (fareMatch != null) {
      final digits = fareMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      grossFare = int.tryParse(digits) ?? 0;
    }

    final lines = normalized
        .split(RegExp(r'\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final fromLines = _parseAddressesFromLines(lines);
    startAddress = fromLines.$1;
    endAddress = fromLines.$2;

    if ((startAddress.isEmpty || endAddress.isEmpty) && blocks != null && blocks.isNotEmpty) {
      final sorted = List<TextBlock>.from(blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      final fromBlocks = _parseAddressesFromBlocks(sorted);
      if (startAddress.isEmpty) startAddress = fromBlocks.$1;
      if (endAddress.isEmpty) endAddress = fromBlocks.$2;
    }

    if (driveDateYmd.isEmpty &&
        driveStartTimeHm.isEmpty &&
        grossFare == 0 &&
        startAddress.isEmpty &&
        endAddress.isEmpty) {
      return null;
    }

    return TmapTripDetailParsed(
      driveDateYmd: driveDateYmd,
      driveStartTimeHm: driveStartTimeHm,
      grossFare: grossFare,
      startAddress: startAddress,
      endAddress: endAddress,
    );
  }

  static (String, String) _parseAddressesFromLines(List<String> lines) {
    String start = '';
    String end = '';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line == '출발') {
        if (i + 1 < lines.length) {
          final next = lines[i + 1];
          if (!next.startsWith('도착') && !_isNoiseLine(next)) start = next;
        }
      } else if (RegExp(r'^출발\s').hasMatch(line) && line.length > 5) {
        final rest = line.replaceFirst(RegExp(r'^출발\s*:?\s*'), '').trim();
        if (rest.isNotEmpty && !rest.contains('도착')) start = rest;
      }

      if (line == '도착') {
        if (i + 1 < lines.length) {
          final next = lines[i + 1];
          if (!_isNoiseLine(next) && !next.contains('실수익')) end = next;
        }
      } else if (RegExp(r'^도착\s').hasMatch(line) && line.length > 5) {
        final rest = line.replaceFirst(RegExp(r'^도착\s*:?\s*'), '').trim();
        if (rest.isNotEmpty && !rest.contains('출발')) end = rest;
      }
    }
    return (start, end);
  }

  static bool _isNoiseLine(String line) {
    final t = line.replaceAll(RegExp(r'\s'), '');
    return t.contains('보험') ||
        t.contains('사고접수') ||
        t == '운행번호' ||
        t.contains('운행상세정보');
  }

  static (String, String) _parseAddressesFromBlocks(List<TextBlock> sorted) {
    String start = '';
    String end = '';
    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i].text.trim();
      if (t == '출발' && i + 1 < sorted.length) {
        final n = sorted[i + 1].text.trim();
        if (n.length > 5 && !n.startsWith('도착')) start = n;
      } else if (t.startsWith('출발') && t.length > 6) {
        final rest = t.replaceFirst(RegExp(r'^출발\s*:?\s*'), '').trim();
        if (rest.length > 5) start = rest;
      }
      if (t == '도착' && i + 1 < sorted.length) {
        final n = sorted[i + 1].text.trim();
        if (n.length > 5) end = n;
      } else if (t.startsWith('도착') && t.length > 6) {
        final rest = t.replaceFirst(RegExp(r'^도착\s*:?\s*'), '').trim();
        if (rest.length > 5) end = rest;
      }
    }
    return (start, end);
  }
}

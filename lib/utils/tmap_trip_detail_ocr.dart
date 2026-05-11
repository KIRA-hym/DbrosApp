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
///
/// 규칙 (텍스트 순서 기준):
/// 1) 「운행일자」 다음 구간에서 `xxxx.x.xx` → 운행일자
/// 2) 1)에서 잡은 날짜 문자열 **뒤** 첫 `xx:xx` → 운행 시작 시각
/// 3) 「출발」 다음 ~ 「도착」 직전 → 출발지
/// 4) 「도착」 다음 ~ 「실수익」 직전 → 도착지
/// 5) 「실수익」 다음 `xx,xxx` 형태 중 `P` 앞 숫자 → 요금
class TmapTripDetailOcr {
  TmapTripDetailOcr._();

  /// 「운행 상세 정보」 타이틀 또는 티맵 대리 영수증 패턴
  static bool isTripDetailScreen(String fullText) {
    final c = fullText.replaceAll(RegExp(r'\s'), '');
    if (c.contains('운행상세정보')) return true;
    if ((c.contains('운행중') || c.contains('운행완료')) &&
        c.contains('실수익') &&
        (c.contains('티맵으로길안내') || c.contains('티맵'))) {
      return true;
    }
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

  /// [fullText]: ML Kit `RecognizedText.text`, [blocks]: 라벨·값 세로 분리 시 보조
  static TmapTripDetailParsed? tryParse(String fullText, {List<TextBlock>? blocks}) {
    if (!isTripDetailScreen(fullText)) return null;

    final normalized = fullText.replaceAll('\r', '\n');

    var driveDateYmd = '';
    var driveStartTimeHm = '';
    var grossFare = 0;
    var startAddress = '';
    var endAddress = '';

    void apply(String source) {
      final dt = _parseDriveDateTime(source);
      if (driveDateYmd.isEmpty && dt.$1.isNotEmpty) driveDateYmd = dt.$1;
      if (driveStartTimeHm.isEmpty && dt.$2.isNotEmpty) driveStartTimeHm = dt.$2;
      if (grossFare == 0) grossFare = _parseGrossFare(source);
      final addr = _parseAddresses(source);
      if (startAddress.isEmpty && addr.$1.isNotEmpty) startAddress = addr.$1;
      if (endAddress.isEmpty && addr.$2.isNotEmpty) endAddress = addr.$2;
      if (startAddress.isEmpty || endAddress.isEmpty) {
        final alt = _parseInProgressCardAddresses(source);
        if (startAddress.isEmpty && alt.$1.isNotEmpty) startAddress = alt.$1;
        if (endAddress.isEmpty && alt.$2.isNotEmpty) endAddress = alt.$2;
      }
    }

    apply(normalized);

    if ((startAddress.isEmpty || endAddress.isEmpty || driveDateYmd.isEmpty) &&
        blocks != null &&
        blocks.isNotEmpty) {
      final sorted = List<TextBlock>.from(blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      final joined = sorted.map((b) => b.text.trim()).where((t) => t.isNotEmpty).join('\n');
      if (joined.isNotEmpty && joined != normalized) {
        apply(joined);
      }
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

  /// 1)·2) 운행일자 키워드 이후 날짜·시각 (없으면 레거시 한 줄 패턴)
  static (String, String) _parseDriveDateTime(String normalized) {
    var driveDateYmd = '';
    var driveStartTimeHm = '';

    const kw = '운행일자';
    final kwIdx = normalized.indexOf(kw);
    if (kwIdx >= 0) {
      final scanAfterKw = normalized.substring(kwIdx + kw.length);
      final dateM = RegExp(r'(\d{4})\.(\d{1,2})\.(\d{1,2})').firstMatch(scanAfterKw);
      if (dateM != null) {
        final y = int.parse(dateM.group(1)!);
        final mo = int.parse(dateM.group(2)!);
        final d = int.parse(dateM.group(3)!);
        driveDateYmd = DateFormat('yyyy-MM-dd').format(DateTime(y, mo, d));
        final afterDate = scanAfterKw.substring(dateM.end);
        final timeM = RegExp(r'(\d{1,2}:\d{2})').firstMatch(afterDate);
        if (timeM != null) {
          final raw = timeM.group(1)!;
          driveStartTimeHm = normalizeDriveTimeHm(raw) ?? raw;
        }
      }
    }

    if (driveDateYmd.isEmpty || driveStartTimeHm.isEmpty) {
      final trip = RegExp(
        r'(\d{4})\.(\d{1,2})\.(\d{1,2})\s*\([^)]*\)\s*(\d{1,2}:\d{2})\s*~\s*(\d{1,2}:\d{2})',
      ).firstMatch(normalized);
      if (trip != null) {
        if (driveDateYmd.isEmpty) {
          final y = int.parse(trip.group(1)!);
          final mo = int.parse(trip.group(2)!);
          final d = int.parse(trip.group(3)!);
          driveDateYmd = DateFormat('yyyy-MM-dd').format(DateTime(y, mo, d));
        }
        if (driveStartTimeHm.isEmpty) {
          final rawStart = trip.group(4)!;
          driveStartTimeHm = normalizeDriveTimeHm(rawStart) ?? rawStart;
        }
      }
    }

    return (driveDateYmd, driveStartTimeHm);
  }

  /// 3)·4) 출발···도착 / 도착···실수익
  static (String, String) _parseAddresses(String normalized) {
    const startKw = '출발';
    const endKw = '도착';
    const fareKw = '실수익';

    final iStart = normalized.indexOf(startKw);
    final iEnd = iStart >= 0 ? normalized.indexOf(endKw, iStart + startKw.length) : normalized.indexOf(endKw);
    final iFare = iEnd >= 0 ? normalized.indexOf(fareKw, iEnd + endKw.length) : normalized.indexOf(fareKw);

    var startAddress = '';
    var endAddress = '';
    if (iStart >= 0 && iEnd > iStart) {
      startAddress = _cleanAddressChunk(normalized.substring(iStart + startKw.length, iEnd));
    }
    if (iEnd >= 0 && iFare > iEnd) {
      endAddress = _cleanAddressChunk(normalized.substring(iEnd + endKw.length, iFare));
    }
    return (startAddress, endAddress);
  }

  static String _cleanAddressChunk(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceFirst(RegExp(r'^[:\s·\-]+'), '');
    return s.trim();
  }

  /// 5) 실수익 다음 `숫자(,)` … `P`
  static int _parseGrossFare(String normalized) {
    final flat = normalized.replaceAll(RegExp(r'\s+'), ' ');
    final fareMatch = RegExp(
      r'실수익\s*[:\s]*([\d,]+)\s*P',
      caseSensitive: false,
    ).firstMatch(flat);
    if (fareMatch != null) {
      final digits = fareMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(digits) ?? 0;
    }
    final loose = RegExp(r'실수익\s*[:\s]*([\d,]+)', caseSensitive: false).firstMatch(flat);
    if (loose == null) return 0;
    final digits = loose.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  /// 티맵 「운행중 콜카드」 형태:
  /// - 상단 상태/버튼 줄
  /// - 출발지 1줄
  /// - 도착지 1줄
  /// - `실수익` 줄
  static (String, String) _parseInProgressCardAddresses(String source) {
    final lines = source
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.length < 3) return ('', '');

    final candidates = <String>[];
    for (final line in lines) {
      if (_isInProgressNoiseLine(line)) continue;
      if (!_looksLikeAddress(line)) continue;
      candidates.add(line);
    }
    if (candidates.length < 2) return ('', '');
    return (candidates[0], candidates[1]);
  }

  static bool _isInProgressNoiseLine(String line) {
    final t = line.replaceAll(RegExp(r'\s+'), '');
    if (t.contains('고객센터') || t.contains('사고신고')) return true;
    if (t.contains('운행중') || t.contains('운행완료')) return true;
    if (t.contains('티맵으로길안내') || t.contains('티맵고객이선호')) return true;
    if (t.contains('실수익')) return true;
    if (t.contains('밀어서고객에게도착알림')) return true;
    if (t.contains('길찾기') || t.contains('위치정보')) return true;
    return false;
  }

  static bool _looksLikeAddress(String line) {
    final t = line.trim();
    if (t.length < 6) return false;
    if (RegExp(r'^[\d,]+\s*P?$').hasMatch(t)) return false;
    if (RegExp(r'(시|군|구|동|읍|면|로|길)').hasMatch(t)) return true;
    // 상호명만 짧게 떨어지는 OCR 방어: 숫자 번지/동/호가 있으면 주소 후보 허용
    if (RegExp(r'\d').hasMatch(t) && RegExp(r'(동|호|번지|아파트|상가)').hasMatch(t)) return true;
    return false;
  }
}

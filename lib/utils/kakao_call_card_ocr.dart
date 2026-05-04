import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'drive_time_format.dart';

/// 카카오 콜카드 OCR: 프로그램 구분(일반·프콜) + 일반 화면 필드(현금·카드 요금 포함).
class KakaoCallCardOcr {
  KakaoCallCardOcr._();

  static const String programGeneral = '카카오(일반)';
  static const String programPro = '카카오(프콜)';

  /// 공백 제거 후 부분 문자열 검사용.
  static String _compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  static bool _assignmentComplete(String n) =>
      n.contains('배정완료') || (n.contains('배정') && n.contains('완료'));

  static bool _tPhone(String n) => n.contains('T전화');

  /// 인식 순서: 일반 1종 → 프콜 1종 → 프콜 2종 → 일반 2종 → `고객과 통화` 단독.
  /// 해당 없으면 `null` (카카오 아님).
  static String? detectKakaoProgram(String fullText) {
    final n = _compact(fullText);
    if (n.isEmpty) return null;

    final hasCallCustomer = n.contains('고객과통화');
    final assignment = _assignmentComplete(n);
    final tPhone = _tPhone(n);
    final hasOpsCenter = n.contains('운영센터');
    final hasSituation = n.contains('상황실');
    final hasCorporate = n.contains('법인');

    // 1. 카카오(일반) 1종: 배정 완료 + 고객과 통화
    if (hasCallCustomer && assignment) {
      return programGeneral;
    }

    // 2. 카카오(프콜) 1종: 배정 완료 + 운영센터 (프콜 2종에는 운영센터 없음)
    if (assignment && hasOpsCenter) {
      return programPro;
    }

    // 3. 카카오(프콜) 2종: T 전화 + 상황실 + 법인, 운영센터 없음
    if (tPhone && hasSituation && hasCorporate && !hasOpsCenter) {
      return programPro;
    }

    // 4. 카카오(일반) 2종: T 전화 + 상황실 + 법인 없음
    if (tPhone && hasSituation && !hasCorporate) {
      return programGeneral;
    }

    // 5. 배정 완료 OCR 누락 등 — 고객과 통화만으로 일반
    if (hasCallCustomer) {
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
        if (a != null && b != null && a + b > 0) return a + b;
      }
    }

    final withP = _lastMatch(RegExp(r'수익\s*([\d,]+)\s*P', caseSensitive: false), flat);
    if (withP != null) {
      final v = _parseCommaInt(withP.group(1)!);
      if (v != null && v > 0) return v;
    }

    final loose = _lastMatch(RegExp(r'수익\s*([\d,]+)(?:\s|$|원|P)', caseSensitive: false), flat);
    if (loose != null) {
      final v = _parseCommaInt(loose.group(1)!);
      if (v != null && v > 0) return v;
    }

    return null;
  }

  /// OCR 블록 기준: 화면 **아래쪽**(큰 `top`) `수익` 줄 우선, 같은 줄·다음 줄 숫자 인식.
  static int? parseKakaoCashGrossFareFromBlocks(List<TextBlock> sorted) {
    final byDescTop = List<TextBlock>.from(sorted)
      ..sort((a, b) => b.boundingBox.top.compareTo(a.boundingBox.top));

    for (final b in byDescTop) {
      final text = b.text.trim();
      if (!text.contains('수익')) continue;

      final sumPatterns = <RegExp>[
        RegExp(r'수익\s*([\d,]+)\s*P?\s*\+\s*지원금\s*([\d,]+)\s*P?', caseSensitive: false),
        RegExp(r'수익\s*([\d,]+)\s*\+\s*지원금\s*([\d,]+)', caseSensitive: false),
      ];
      for (final re in sumPatterns) {
        final m = re.firstMatch(text);
        if (m != null) {
          final a = _parseCommaInt(m.group(1)!);
          final bAmt = _parseCommaInt(m.group(2)!);
          if (a != null && bAmt != null && a + bAmt > 0) return a + bAmt;
        }
      }
      final withP = RegExp(r'수익\s*([\d,]+)\s*P', caseSensitive: false).firstMatch(text);
      if (withP != null) {
        final v = _parseCommaInt(withP.group(1)!);
        if (v != null && v > 0) return v;
      }
      final loose = RegExp(r'수익\s*([\d,]+)(?:\s|$|원|P)', caseSensitive: false).firstMatch(text);
      if (loose != null) {
        final v = _parseCommaInt(loose.group(1)!);
        if (v != null && v > 0) return v;
      }
    }

    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i].text.trim();
      if (!t.contains('수익')) continue;
      if (RegExp(r'수익\s*[\d,]').hasMatch(t)) continue;
      if (i + 1 >= sorted.length) continue;
      final next = sorted[i + 1].text.trim();
      final m = RegExp(r'^([\d,]+)\s*P?$').firstMatch(next);
      if (m != null) {
        final v = _parseCommaInt(m.group(1)!);
        if (v != null && v > 0) return v;
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
    if (RegExp(r'배정|메뉴|완료|취소').hasMatch(t)) return true;
    return _excludePaymentOrActionStrip(t);
  }

  /// 도착지 밴드에 끼어드는 요금·버튼 줄 제외.
  static bool _excludeFromEndLocation(String text) {
    return _excludePaymentOrActionStrip(text);
  }

  static bool _excludePaymentOrActionStrip(String text) {
    final t = text.trim();
    if (t.length <= 6) {
      const shortUi = {'고객', '메모', '상황실', '운영센터', '메뉴'};
      if (shortUi.contains(t)) return true;
    }
    if (t.contains('현금') && t.contains('확정')) return true;
    if (t.contains('카드') && t.contains('확정')) return true;
    if (t.contains('지원금')) return true;
    if (t.contains('수익') && RegExp(r'\d').hasMatch(t)) return true;
    if (t.contains('밀어서') || t.contains('도착알림')) return true;
    if (t.contains('길찾기')) return true;
    return false;
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

    for (final b in sorted) {
      final y = b.boundingBox.top;
      final text = b.text.trim();

      if (y < 200) {
        final dateMatch = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(text);
        if (dateMatch != null) {
          parsedDate =
              '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}';
        }
        final timeMatch = RegExp(r'\d{1,2}:\d{1,2}').firstMatch(text);
        if (timeMatch != null) {
          parsedTime = normalizeDriveTimeHm(timeMatch.group(0)!) ?? timeMatch.group(0)!;
        }
      }

      if (y > 500 && y < 900 && !_excludeFromStartLocation(text)) {
        startBuf.write('$text ');
      }
      if (y > 900 && y < 1400 && !_excludeFromEndLocation(text)) {
        endBuf.write('$text ');
      }
    }

    parsedWaypoint = _mergeWaypointFromBlocks(sorted);

    if (looksLikeKakaoCashPayment(fullText)) {
      parsedIncome = parseKakaoCashGrossFareFromBlocks(sorted) ?? parseKakaoCashGrossFare(fullText);
    }

    if (parsedIncome == null) {
      for (final b in sorted) {
        final y = b.boundingBox.top;
        final text = b.text.trim();
        if (y > 1400 && text.contains(RegExp(r'\d{3,}'))) {
          if (RegExp(r'^\d{1,3}점$').hasMatch(text.replaceAll(',', ''))) continue;
          final cleanNum = text.replaceAll(RegExp(r'[^0-9]'), '');
          if (cleanNum.length >= 4) {
            parsedIncome = int.tryParse(cleanNum);
            if (parsedIncome != null) break;
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

  KakaoScreenParsed({
    required this.driveDateYmd,
    required this.driveTimeHm,
    required this.waypoint,
    required this.startLocation,
    required this.endLocation,
    required this.grossFare,
  });
}

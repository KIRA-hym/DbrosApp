import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'drive_time_format.dart';
import 'kakao_call_card_ocr.dart';

/// 카카오 **맞춤콜** 배차 화면 (일반·프콜과 다른 UI).
class KakaoCustomCallOcr {
  KakaoCustomCallOcr._();

  static const String programCustom = '카카오(맞춤)';

  static String _compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  static bool isCustomCallScreen(String fullText) =>
      _compact(fullText).contains('맞춤콜');

  /// 도착 문자열에서 하트·유사 기호만 제거 (주소는 유지).
  static String stripHeartDecorations(String input) {
    var s = input;
    const literal = [
      '🤍', '♡', '♥', '💛', '💚', '💙', '💜', '🖤', '🧡', '💕', '💖', '❤️', '❤',
    ];
    for (final h in literal) {
      s = s.replaceAll(h, '');
    }
    s = s.replaceAll(RegExp(r'[\u2661\u2665\u2764\uFE0F]'), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isMapRouteNoise(String t) {
    final u = t.trim();
    if (u.contains('도보')) return true;
    if (RegExp(r'\d+\.\d+\s*km', caseSensitive: false).hasMatch(u)) return true;
    if (u.contains('약') && u.contains('분') && u.contains('운행')) return true;
    return false;
  }

  /// `실제 수익` 근처 또는 전체에서 `[금액] P` (3자리 이상) 첫 매칭.
  static int? parseProfitBeforeP(String fullText) {
    final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ');
    var slice = flat;
    final idx = flat.indexOf('실제');
    if (idx >= 0) {
      slice = flat.substring(idx);
    }
    final m = RegExp(r'([\d,]{3,})\s*P').firstMatch(slice);
    if (m != null) {
      final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    final m2 = RegExp(r'([\d,]{3,})\s*P').firstMatch(flat);
    if (m2 != null) {
      final v = int.tryParse(m2.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    return null;
  }

  static String? _extractLabeledPlace(
    List<TextBlock> sorted,
    String label,
  ) {
    for (var i = 0; i < sorted.length; i++) {
      final raw = sorted[i].text.trim();
      final t = raw.replaceAll(RegExp(r'\s+'), ' ');
      if (!t.contains(label)) continue;

      if (t == label || t == '$label:' || t == '$label :') {
        for (var j = i + 1; j < sorted.length && j < i + 6; j++) {
          final u = sorted[j].text.trim();
          if (u.startsWith('출발') || u.startsWith('도착')) continue;
          if (_isMapRouteNoise(u)) continue;
          if (u.contains('실제') && u.contains('수익')) continue;
          if (u.length >= 2) return u;
        }
        continue;
      }

      if (t.startsWith(label)) {
        var rest = t.substring(label.length).replaceFirst(RegExp(r'^[:\s]+'), '').trim();
        rest = rest.replaceFirst(RegExp(r'^[\|\s]+'), '').trim();
        if (rest.isNotEmpty && !_isMapRouteNoise(rest)) {
          return rest;
        }
      }
    }

    final full = sorted.map((b) => b.text).join('\n');
    final esc = RegExp.escape(label);
    final lineRe = RegExp('$esc\\s*[:\\s]*([^\\n]+)');
    final lm = lineRe.firstMatch(full);
    if (lm != null) {
      var rest = lm.group(1)!.trim();
      rest = rest.split(RegExp(r'(?=도착|실제\s*수익)')).first.trim();
      if (rest.isNotEmpty && !_isMapRouteNoise(rest)) {
        return rest;
      }
    }
    return null;
  }

  /// 상단(y&lt;200) 날짜·시:분, 출발/도착 라벨, 실제 수익 줄의 P 앞 숫자.
  /// 운행시간은 **약 N분 운행**이 아니라 상단 시각만 사용.
  static KakaoScreenParsed parseScreen(List<TextBlock> blocks, String fullText) {
    String? parsedDate;
    String? parsedTime;

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
    }

    final start = _extractLabeledPlace(sorted, '출발') ?? '';
    final endRaw = _extractLabeledPlace(sorted, '도착') ?? '';
    final end = stripHeartDecorations(endRaw);

    final fare = parseProfitBeforeP(fullText);

    return KakaoScreenParsed(
      driveDateYmd: parsedDate,
      driveTimeHm: parsedTime,
      waypoint: '',
      startLocation: start,
      endLocation: end,
      grossFare: fare,
    );
  }
}

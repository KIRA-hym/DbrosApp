import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

  /// `실제 수익 카드 | 확정 | 36,000 P` 형태를 분해.
  static ({String? paymentMethod, int? amount}) parsePaymentAndFare(String fullText) {
    final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final m = RegExp(
      r'실제\s*(?:수익\s*)?([^\s|]+)?\s*\|\s*([^|\n]+?)\s*\|\s*([\d,]{3,})\s*(?:P|원|®|©|p)?',
      caseSensitive: false,
    ).firstMatch(flat);
    if (m != null) {
      final method = m.group(1)?.trim();
      final amount = int.tryParse((m.group(3) ?? '').replaceAll(',', ''));
      return (paymentMethod: method, amount: amount);
    }
    
    // Fallback: 실제 옆의 첫 3자리 이상 숫자 매칭
    final idx = flat.indexOf('실제');
    if (idx >= 0) {
      final slice = flat.substring(idx);
      final m2 = RegExp(r'([\d,]{3,})').firstMatch(slice);
      if (m2 != null) {
        final amount = int.tryParse(m2.group(1)!.replaceAll(',', ''));
        final method = slice.contains('카드')
            ? '카드'
            : (slice.contains('현금') ? '현금' : null);
        return (paymentMethod: method, amount: amount);
      }
    }
    return (paymentMethod: null, amount: null);
  }

  /// `실제 수익` 근처 또는 전체에서 `[금액] P` (3자리 이상) 첫 매칭.
  static int? parseProfitBeforeP(String fullText) {
    final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ');
    var slice = flat;
    final idx = flat.indexOf('실제');
    if (idx >= 0) {
      slice = flat.substring(idx);
    }
    final m = RegExp(r'([\d,]{3,})\s*(?:P|원|®|©|p)?').firstMatch(slice);
    if (m != null) {
      final v = int.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    final m2 = RegExp(r'([\d,]{3,})\s*(?:P|원|®|©|p)?').firstMatch(flat);
    if (m2 != null) {
      final v = int.tryParse(m2.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    return null;
  }

  static String? _extractLabeledPlace(
    List<TextBlock> sorted,
    String label,
    String fullText,
  ) {
    for (var i = 0; i < sorted.length; i++) {
      final raw = sorted[i].text.trim();
      final t = raw.replaceAll(RegExp(r'\s+'), ' ');
      if (!t.contains(label)) continue;

      if (t == label || t == '$label:' || t == '$label :') {
        final parts = <String>[];
        for (var j = i + 1; j < sorted.length && j < i + 6; j++) {
          final u = sorted[j].text.trim();
          if (u.startsWith('출발') || u.startsWith('도착')) break;
          if (_isMapRouteNoise(u)) continue;
          if (u.contains('실제') && u.contains('수익')) break;
          if (u.length >= 2) parts.add(u);
        }
        if (parts.isNotEmpty) return parts.join(' ');
        continue;
      }

      if (t.startsWith(label)) {
        var rest = t.substring(label.length).replaceFirst(RegExp(r'^[:\s]+'), '').trim();
        rest = rest.replaceFirst(RegExp(r'^[\|\s]+'), '').trim();
        final parts = <String>[];
        if (rest.isNotEmpty && !_isMapRouteNoise(rest)) parts.add(rest);
        for (var j = i + 1; j < sorted.length && j < i + 6; j++) {
          final u = sorted[j].text.trim();
          if (u.startsWith('출발') || u.startsWith('도착')) break;
          if (_isMapRouteNoise(u)) continue;
          if (u.contains('실제') && u.contains('수익')) break;
          if (u.length >= 2) parts.add(u);
        }
        if (parts.isNotEmpty) return parts.join(' ');
      }
    }

    final lines = fullText
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.startsWith(label)) continue;
      var rest = line.substring(label.length).replaceFirst(RegExp(r'^[:\s]+'), '').trim();
      rest = rest.replaceFirst(RegExp(r'^[\|\s]+'), '').trim();
      rest = rest.split(RegExp(r'(?=도착|실제\s*수익)')).first.trim();
      final parts = <String>[];
      if (rest.isNotEmpty && !_isMapRouteNoise(rest)) parts.add(rest);
      for (var j = i + 1; j < lines.length && j < i + 6; j++) {
        final next = lines[j];
        if (next.startsWith('출발') || next.startsWith('도착')) break;
        if (_isMapRouteNoise(next)) continue;
        if (next.contains('실제') && next.contains('수익')) break;
        if (next.length >= 2) parts.add(next);
      }
      if (parts.isNotEmpty) return parts.join(' ');
    }
    return null;
  }

  /// 출발/도착 라벨, 실제 수익 줄의 P 앞 숫자를 파싱한다.
  /// 날짜/시간은 이미지 Exif 메타데이터를 사용하므로 OCR에서 추출하지 않는다.
  static KakaoScreenParsed parseScreen(List<TextBlock> blocks, String fullText) {
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    var start = _extractLabeledPlace(sorted, '출발', fullText) ?? '';
    var endRaw = _extractLabeledPlace(sorted, '도착', fullText) ?? '';

    // Heuristic fallback if addresses are empty, contain map noise, or are invalid Korean addresses
    if (start.isEmpty || _isMapRouteNoise(start) || start.contains('맞춤콜') || start.contains('고속도로') ||
        endRaw.isEmpty || _isMapRouteNoise(endRaw) || endRaw.contains('맞춤콜') || endRaw.contains('고속도로') ||
        !_isValidKoreanAddress(start) || !_isValidKoreanAddress(endRaw)) {
      final heuristicAddr = _parseAddressesHeuristically(fullText);
      if (heuristicAddr.start.isNotEmpty &&
          (start.isEmpty || !_isValidKoreanAddress(start) || start.contains('맞춤콜') || start.contains('고속도로'))) {
        start = heuristicAddr.start;
      }
      if (heuristicAddr.end.isNotEmpty &&
          (endRaw.isEmpty || !_isValidKoreanAddress(endRaw) || endRaw.contains('맞춤콜') || endRaw.contains('고속도로'))) {
        endRaw = heuristicAddr.end;
      }
    }

    final end = stripHeartDecorations(endRaw);

    final income = parsePaymentAndFare(fullText);
    final fare = income.amount ?? parseProfitBeforeP(fullText);

    return KakaoScreenParsed(
      driveDateYmd: null,
      driveTimeHm: null,
      waypoint: '',
      startLocation: start,
      endLocation: end,
      grossFare: fare,
      paymentMethod: income.paymentMethod,
    );
  }

  static bool _isValidKoreanAddress(String text) {
    final t = text.trim();
    if (t.length < 5) return false;
    final hasProvince = RegExp(r'^(서울|경기|인천|강원|충북|충남|전북|전남|경북|경남|부산|대구|광주|대전|울산|세종|제주)').hasMatch(t);
    final hasStructure = RegExp(r'([시구동읍면로길]|\d+-\d+)').hasMatch(t);
    if (t.contains('고속도로') || t.contains('간선') || t.contains('순환로')) return false;
    if (t.contains('프로') || t.contains('단독') || t.contains('배정') || t.contains('추천') || t.contains('자동')) return false;
    return hasProvince || (hasStructure && t.split(' ').length >= 2);
  }

  static ({String start, String end}) _parseAddressesHeuristically(String fullText) {
    final lines = fullText
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String startAddress = '';
    String endAddress = '';

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('출발')) {
        var rest = line.substring(2).trim();
        rest = rest.replaceFirst(RegExp(r'^[:\s|]+'), '').trim();
        if (rest.isNotEmpty && !_isMapRouteNoise(rest)) {
          startAddress = rest;
          break;
        }
        for (var j = i + 1; j < lines.length && j < i + 4; j++) {
          final next = lines[j];
          if (next.startsWith('출발') || next.startsWith('도착') || next.contains('실제')) break;
          if (_isMapRouteNoise(next)) continue;
          if (_isValidKoreanAddress(next)) {
            startAddress = next;
            break;
          }
        }
        if (startAddress.isNotEmpty) break;
      }
    }

    final List<String> addressCandidates = [];
    for (final line in lines) {
      if (line.startsWith('출발') || line.startsWith('도착') || line.contains('실제') || line.contains('수익')) continue;
      if (_isMapRouteNoise(line)) continue;
      if (_isValidKoreanAddress(line)) {
        addressCandidates.add(line);
      }
    }

    addressCandidates.removeWhere((c) => c == startAddress || startAddress.contains(c));

    if (addressCandidates.isNotEmpty) {
      final provCandidate = addressCandidates.firstWhere(
        (c) => RegExp(r'^(서울|경기|인천|강원|충북|충남|전북|전남|경북|경남|부산|대구|광주|대전|울산|세종|제주)').hasMatch(c),
        orElse: () => addressCandidates.first,
      );
      endAddress = provCandidate;
    }

    return (start: startAddress, end: endAddress);
  }
}

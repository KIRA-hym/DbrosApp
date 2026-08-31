import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/remote_config_service.dart';
import '../services/ocr_error_logger.dart';

/// T맵 대리 「운행 상세 정보」 파싱 결과
class TmapTripDetailParsed {
  TmapTripDetailParsed({
    required this.grossFare,
    required this.startAddress,
    required this.endAddress,
    this.waypoint,
    // 날짜/시간은 이미지 Exif 메타데이터를 사용하므로 항상 빈 문자열
    this.driveDateYmd = '',
    this.driveStartTimeHm = '',
  });

  final String driveDateYmd;
  final String driveStartTimeHm;
  final int grossFare;
  final String startAddress;
  final String endAddress;
  final String? waypoint;
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

    var grossFare = 0;
    var startAddress = '';
    var endAddress = '';
    var waypoint = '';

    void apply(String source) {
      if (grossFare == 0) grossFare = _parseGrossFare(source);
      final addr = _parseAddresses(source);
      if (startAddress.isEmpty && addr.$1.isNotEmpty) startAddress = addr.$1;
      if (endAddress.isEmpty && addr.$2.isNotEmpty) endAddress = addr.$2;
      if (startAddress.isEmpty || endAddress.isEmpty) {
        final alt = _parseInProgressCardAddresses(source);
        if (startAddress.isEmpty && alt.$1.isNotEmpty) startAddress = alt.$1;
        if (waypoint.isEmpty && alt.$2.isNotEmpty) waypoint = alt.$2;
        if (endAddress.isEmpty && alt.$3.isNotEmpty) endAddress = alt.$3;
      }
    }

    apply(normalized);

    if ((startAddress.isEmpty || endAddress.isEmpty) && blocks != null && blocks.isNotEmpty) {
      final sorted = List<TextBlock>.from(blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      final joined = sorted.map((b) => b.text.trim()).where((t) => t.isNotEmpty).join('\n');
      if (joined.isNotEmpty && joined != normalized) {
        apply(joined);
      }
    }

    // Clear false positives from horizontal parsing
    if (startAddress.contains('\uC6B4\uD589\uC77C\uC790') || startAddress.contains('\uC6B4\uD589\uBC88\uD638') || startAddress.contains('\uC694\uAE30\uC694')) startAddress = '';
    if (endAddress.contains('\uC6B4\uD589\uC77C\uC790') || endAddress.contains('\uC6B4\uD589\uBC88\uD638') || endAddress.contains('\uC694\uAE30\uC694')) endAddress = '';

    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---
    if (startAddress.isEmpty || endAddress.isEmpty) {
      final lines = normalized.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final infoIdx = lines.indexWhere((e) => e.replaceAll(RegExp(r'\s+'), '') == '운행상세정보');
      if (infoIdx != -1 && infoIdx + 2 < lines.length) {
        final s = lines[infoIdx + 1];
        final e = lines[infoIdx + 2];
        if (startAddress.isEmpty && s.length > 3 && !s.contains(RegExp(r'[\d,]+\s*[P원]$')) && !s.contains('운행') && !s.contains('보험')) {
          startAddress = s;
        }
        if (endAddress.isEmpty && e.length > 3 && !e.contains(RegExp(r'[\d,]+\s*[P원]$')) && !e.contains('운행') && !e.contains('보험')) {
          endAddress = e;
        }
      }
    }

    if (grossFare == 0) {
      final fareMatch = RegExp(r'([\d,]+)\s*P').firstMatch(normalized.replaceAll(RegExp(r'\s+'), ' '));
      if (fareMatch != null) {
        grossFare = int.tryParse(fareMatch.group(1)!.replaceAll(',', '')) ?? 0;
      }
    }
    // ---------------------------------------------------

    if (grossFare == 0 && startAddress.isEmpty && endAddress.isEmpty) {
      return null;
    }

    var driveDateYmd = '';
    var driveStartTimeHm = '';
    final flat = normalized.replaceAll(RegExp(r'\s+'), ' ');
    final dtMatch = RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})').firstMatch(flat);
    if (dtMatch != null) {
      final y = dtMatch.group(1)!;
      final m = dtMatch.group(2)!.padLeft(2, '0');
      final d = dtMatch.group(3)!.padLeft(2, '0');
      driveDateYmd = '$y-$m-$d';
      driveStartTimeHm = dtMatch.group(4)!.replaceAll(' ', '');
    }

    // Cleanup garbage appended by ML Kit grouping
    String cleanAddr(String a) {
      if (a.isEmpty) return a;
      var res = a;
      final fareMatch = RegExp(r'\d{1,3}(,\d{3})*\s*[P원]').firstMatch(res);
      if (fareMatch != null) res = res.substring(0, fareMatch.start);
      final insIdx = res.indexOf('보험');
      if (insIdx != -1) res = res.substring(0, insIdx);
      return res.trim();
    }
    startAddress = cleanAddr(startAddress);
    endAddress = cleanAddr(endAddress);

    if (startAddress.isEmpty || endAddress.isEmpty || grossFare == 0) {
      OcrErrorLoggerService.instance.logError(
        platform: 'tmap',
        rawText: fullText,
        errorReason: 'Missing critical fields. start: $startAddress, end: $endAddress, fare: $grossFare',
        parsedData: {
          'gross_fare': grossFare,
          'start_address': startAddress,
          'end_address': endAddress,
          'waypoint': waypoint,
        },
      );
    }

    return TmapTripDetailParsed(
      grossFare: grossFare,
      startAddress: startAddress,
      endAddress: endAddress,
      waypoint: waypoint.isEmpty ? null : waypoint,
      driveDateYmd: driveDateYmd,
      driveStartTimeHm: driveStartTimeHm,
    );
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

  static String _cleanLineBullet(String line) {
    var s = line.trim();
    s = s.replaceFirst(RegExp(r'^[o•*·\-\d]\s+'), '');
    s = s.replaceFirst(RegExp(r'^[o•*·\-]+'), '');
    return s.trim();
  }

  /// 티맵 「운행중 콜카드」 형태:
  /// - 상단 상태/버튼 줄
  /// - 출발지 주소 + 출발지 상호명 (다중 줄 지원)
  /// - 경유지 주소 + 경유지 상호명 (선택)
  /// - 도착지 주소 + 도착지 상호명 (다중 줄 지원)
  /// - `실수익` 줄
  ///
  /// ▶ 핵심 로직 — "주소-우선 그루핑":
  ///   각 위치(location)의 첫 줄은 반드시 [addressStartPattern]에 매치되는
  ///   행정주소여야 한다. 상호명처럼 주소 패턴에 걸리지 않는 줄이
  ///   주소보다 **먼저** 등장할 경우, 해당 줄을 [pendingName] 버퍼에
  ///   임시 보관했다가 다음 주소가 나타나면 그 주소 뒤에 붙인다.
  ///
  /// 예시 (오류 재현 케이스):
  ///   연주음악학원            → pendingName 에 보류
  ///   고양시 일산동구 정발산동 693-9 → locations[0] 생성, pendingName 후미 추가
  ///   군포시 금정동 850        → locations[1] 생성
  ///   목화아파트               → locations[1] 에 append
  ///
  /// 결과: locations[0] = "고양시 일산동구 정발산동 693-9 연주음악학원" (출발지)
  ///       locations[1] = "군포시 금정동 850 목화아파트"             (도착지)
  static (String, String, String) _parseInProgressCardAddresses(String source) {
    // ── 1. 줄 분리 및 공백 정규화 ──────────────────────────────────────
    final lines = source
        .split(RegExp(r'[\r\n]+'))   // 개행 기준으로 분리
        .map((e) => e.trim())        // 앞뒤 공백 제거
        .where((e) => e.isNotEmpty)  // 빈 줄 제거
        .toList();
    if (lines.length < 2) return ('', '', '');

    // ── 2. 시작 구분선: "고객센터/운행중" 이후부터 주소 영역 ─────────────
    // 티맵 콜카드는 상단에 고객센터·운행중 같은 버튼/상태 줄이 있고
    // 그 아래가 실제 주소 영역이다.
    int startIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      final t = lines[i].replaceAll(RegExp(r'\s+'), '');
      if (t.contains('고객센터') || t.contains('운행중') ||
          t.contains('사고신고') || t.contains('소사고신고')) {
        startIdx = i;
        break;
      }
    }

    // ── 3. 종료 구분선: "티맵으로 길안내" 직전까지가 주소 영역 ──────────
    int endIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      final t = lines[i].replaceAll(RegExp(r'\s+'), '');
      if (t.contains('티맵으로길안내') || t.contains('티맵으로') ||
          t.contains('길안내')) {
        endIdx = i;
        break;
      }
    }

    // ── 4. 주소 후보 줄 수집 (노이즈 줄 제외) ────────────────────────────
    final candidates = <String>[];
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx + 1) {
      // 시작·종료 구분선 사이의 줄만 사용
      for (final line in lines.sublist(startIdx + 1, endIdx)) {
        if (!_isInProgressNoiseLine(line)) {
          candidates.add(line);
        }
      }
    } else {
      // 구분선을 찾지 못한 경우: 노이즈만 걸러내고 전체 사용
      for (final line in lines) {
        if (_isInProgressNoiseLine(line)) continue;
        candidates.add(line);
      }
    }

    if (candidates.isEmpty) return ('', '', '');

    // ── 5. 행정주소 시작 판별 정규식 ─────────────────────────────────────
    // Remote Config 에서 가져오거나 오프라인이면 기본값 사용.
    // 패턴 예시: "^[o0•*·\-\s]*(?:경기|서울|...)|[가-힣]{1,5}(?:시|도|군|구)"
    // → "고양시", "경기도", "군포시 금정동" 처럼 행정 단위로 시작하는 줄을 감지
    final RegExp addressStartPattern = RegExp(
      RemoteConfigService().tmapAddressPattern,
    );

    // ── 6. 위치 그루핑: "주소-우선" 방식 ────────────────────────────────
    // locations: 각 위치(출발지·경유지·도착지)를 [주소, 상호명?, ...] 리스트로 저장
    // pendingName: 아직 주소를 만나지 못한 상태에서 나온 상호명 줄(들)을 임시 보관
    //
    //   [AS-IS] 문제 로직:
    //     상호명이 주소보다 먼저 나오면 → locations가 비어있으므로
    //     else 분기의 `locations.add([cleaned])`로 상호명이 첫 위치(출발지)가 됨
    //
    //   [TO-BE] 수정 로직:
    //     주소보다 먼저 온 비-주소 줄 → pendingName 버퍼에 보관
    //     이후 첫 주소 줄이 나타나면  → 해당 위치를 생성하고 pendingName 을 후미에 추가
    //     이미 위치가 있는 상태에서 비-주소 줄이 나오면 → 마지막 위치에 append
    final List<List<String>> locations = [];
    final List<String> pendingName = []; // 아직 주소를 만나지 못한 상호명 보류 버퍼

    for (final line in candidates) {
      final cleaned = _cleanLineBullet(line);
      if (cleaned.isEmpty) continue;

      if (addressStartPattern.hasMatch(line)) {
        // ── 행정주소 시작 줄 감지 ──
        // 중복 주소 방지: 이전 위치의 첫 줄과 문자열 포함 관계 확인
        bool isDuplicate = false;
        if (locations.isNotEmpty) {
          final lastPrimary = locations.last.first;
          final s1 = cleaned.replaceAll(RegExp(r'\s'), '');
          final s2 = lastPrimary.replaceAll(RegExp(r'\s'), '');
          if (s1.contains(s2) || s2.contains(s1)) {
            isDuplicate = true;
            if (s1.length > s2.length) {
              locations.last[0] = cleaned; // 더 긴(정확한) 문자열로 교체
            }
          }
        }
        if (isDuplicate) {
          pendingName.clear(); // 중복 주소면 pendingName 도 버림
          continue;
        }

        // 새 위치 생성: 먼저 주소 줄을 첫 원소로, pendingName 은 후미에 추가
        // 예) "고양시 일산동구 정발산동 693-9" 생성 후 "연주음악학원" 추가
        final newLocation = [cleaned, ...pendingName];
        pendingName.clear(); // 버퍼 비우기
        locations.add(newLocation);

      } else {
        // ── 비-주소 줄 (상호명, 동/호수 보조 정보 등) ──
        if (locations.isNotEmpty) {
          // 이미 주소가 하나 이상 그루핑된 경우 → 마지막 위치에 append
          locations.last.add(cleaned);
        } else {
          // 아직 주소가 하나도 나오지 않은 경우 → pendingName 버퍼에 보관
          // (나중에 첫 주소가 나오면 그 위치의 상호명으로 붙여질 예정)
          pendingName.add(cleaned);
        }
      }
    }

    if (locations.isEmpty) return ('', '', '');

    // ── 7. 출발지 / 경유지 / 도착지 분리 ───────────────────────────────
    // 각 위치의 줄들을 공백으로 합쳐 하나의 문자열로 반환
    // 예) ["고양시 일산동구 정발산동 693-9", "연주음악학원"] → "고양시 일산동구 정발산동 693-9 연주음악학원"
    final start = locations[0].join(' ').trim();

    if (locations.length == 2) {
      // 출발지 + 도착지 (경유지 없음)
      final end = locations[1].join(' ').trim();
      return (start, '', end);
    } else if (locations.length >= 3) {
      // 출발지 + 경유지(들) + 도착지
      final end = locations.last.join(' ').trim();
      final waypointParts = locations.sublist(1, locations.length - 1)
          .map((loc) => loc.join(' ').trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
      return (start, waypointParts, end);
    }

    // 위치가 1개인 경우: 출발지만 존재 (도착지 미인식)
    return (start, '', '');
  }

  static bool _isInProgressNoiseLine(String line) {
    final t = line.replaceAll(RegExp(r'\s+'), '');
    if (t.contains('고객센터') || t.contains('사고신고') || t.contains('소사고신고')) return true;
    if (t.contains('운행중') || t.contains('운행완료')) return true;
    if (t.contains('티맵으로길안내') || t.contains('티맵고객이선호') || t.contains('티맵으로') || t.contains('길안내') || t.contains('티맵')) return true;
    if (t.contains('실수익') || t.contains('실수익금')) return true;
    if (t.contains('밀어서고객에게도착알림') || t.contains('도착알림')) return true;
    if (t.contains('길찾기') || t.contains('위치정보') || t.contains('고객전화')) return true;
    if (RegExp(r'^\d+\s*[m|M]$').hasMatch(t)) return true;
    if (t.toUpperCase() == 'TALK') return true;
    return false;
  }
}

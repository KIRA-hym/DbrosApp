import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

import '../data/repositories/address_repository.dart';
import 'address_normalize.dart';

class GeocodingUtils {
  static bool _localeInitialized = false;

  static final RegExp _sidoPrefixRe = RegExp(
    r'^(?:대한민국\s+)?(?:서울(?:특별시|시)?|부산(?:광역시|시)?|대구(?:광역시|시)?|인천(?:광역시|시)?|광주(?:광역시|시)?|대전(?:광역시|시)?|울산(?:광역시|시)?|세종(?:특별자치시|시)?|경기(?:도)?|강원(?:특별자치도|도)?|충북|충청북도|충남|충청남도|전북|전북특별자치도|전라북도|전남|전라남도|경북|경상북도|경남|경상남도|제주(?:특별자치도|도)?)',
  );

  static final RegExp _adminPrefixRepeatRe = RegExp(
    r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)\s+[가-힣]+(?:시|군|구)(?:\s+[가-힣]+구)?',
  );

  /// 대한민국 영토 바운더리 체크 (위도 33.1~38.6, 경도 124.6~132.0).
  /// `null`, `0.0`, `NaN`, 해외 좌표를 모두 무효 처리합니다.
  static bool isValidSouthKoreaCoord(double? lat, double? lng) {
    if (lat == null || lng == null || lat.isNaN || lng.isNaN) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    return lat >= 33.1 && lat <= 38.6 && lng >= 124.6 && lng <= 132.0;
  }

  static bool _isValidSouthKorea(Location loc) =>
      isValidSouthKoreaCoord(loc.latitude, loc.longitude);

  /// 붙여쓰기된 한국 행정구역을 지오코더가 잘 읽도록 띄어쓰기 보정합니다.
  /// 예) `부천시원미구 중동` → `부천시 원미구 중동`, `본오동963-9` → `본오동 963-9`
  static String _spaceKoreanAdminTokens(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    // 시+구 붙여쓰기 분리 (예: 수원시팔달구 → 수원시 팔달구, 고양시일산동구 → 고양시 일산동구)
    s = s.replaceAllMapped(
      RegExp(r'([가-힣]{2,}시)([가-힣]{1,4}구)(?=\s|$|[가-힣\d])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    // 구+동/읍/면/로/길 붙여쓰기 분리 (예: 강남구역삼동 → 강남구 역삼동)
    s = s.replaceAllMapped(
      RegExp(r'([가-힣]{1,4}구)([가-힣]{1,6}(?:동|읍|면|가|로|길))'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    // 동/읍/면/리/가/로/길 뒤에 숫자 번지가 바로 붙은 경우 분리 (예: 본오동963-9 → 본오동 963-9)
    s = s.replaceAllMapped(
      RegExp(r'([가-힣]{1,8}(?:동|읍|면|리|가|로|길))(\d+(?:-\d+)?)'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 티맵 등에서 같은 시/도+시/군/구가 두 번 반복된 이중 주소에서 뒤쪽 상세 주소를 우선 추출합니다.
  /// 예) `경기 안산시 상록구 본오동 경기 안산시 상록구 본오동 963-9` → `경기 안산시 상록구 본오동 963-9`
  static String? _extractDedupedDetailedAddress(String spaced) {
    final matches = _adminPrefixRepeatRe.allMatches(spaced).toList();
    if (matches.length < 2) return null;
    final p0 = matches[0].group(0)!.replaceAll(RegExp(r'\s+'), ' ');
    final p1 = matches[1].group(0)!.replaceAll(RegExp(r'\s+'), ' ');
    if (p0 == p1) {
      final tail = spaced.substring(matches[1].start).trim();
      if (tail.isNotEmpty && tail != spaced) return tail;
    }
    return null;
  }

  /// 지오코딩 시도 후보 문자열 목록을 우선순위(정밀 → 광역) 순으로 생성합니다.
  static List<String> buildGeocodeCandidates(String address) {
    final addr = address.trim();
    if (addr.isEmpty) return const [];

    final normalized = normalizeAddressForGeocode(addr);
    final base = normalized.isNotEmpty ? normalized : addr;
    final spaced = _spaceKoreanAdminTokens(base);

    final candidates = <String>[];
    void addCandidate(String s) {
      final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty && !candidates.contains(t)) {
        candidates.add(t);
      }
    }

    // 1. 중복 행정구역(티맵 지번+도로명 병기)이 있으면 뒤쪽 상세 주소를 1순위로 시도
    final deduped = _extractDedupedDetailedAddress(spaced);
    if (deduped != null) {
      addCandidate(deduped);
    }

    final primary = deduped ?? spaced;
    addCandidate(primary);
    addCandidate(base);
    addCandidate(addr);

    // 2. 도로명/지번 행정 단위 + 번지/도로번호 보존 폴백
    final tokens = primary.split(RegExp(r'\s+'));
    final List<String> unitTokens = [];
    String? roadSubBranch; // 예: 327번길
    String? numberAfterUnit;
    bool foundUnit = false;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      // 예: "합정동삼아빌딩"처럼 동 뒤에 상호명이 붙여쓰기된 경우 동까지만 절삭
      // 도로명("영동대로", "강동대로")·일반 상호("파리바게뜨") 오절단을 막기 위해 '동' 단위 + 비(로/길/구/시)로 한정
      final gluedDongMatch = RegExp(
        r'^([가-힣]{2,6}동)([가-힣]{2,})$',
      ).firstMatch(t);
      if (gluedDongMatch != null &&
          !t.endsWith('동') &&
          !t.endsWith('구') &&
          !t.endsWith('시') &&
          !t.endsWith('로') &&
          !t.endsWith('길')) {
        unitTokens.add(gluedDongMatch.group(1)!);
        foundUnit = true;
        break;
      }

      unitTokens.add(t);
      final isRoad = t.endsWith('로') || t.endsWith('길');
      final isDong = t.endsWith('동') ||
          t.endsWith('읍') ||
          t.endsWith('면') ||
          t.endsWith('리') ||
          t.endsWith('가');
      if (isRoad || isDong) {
        foundUnit = true;
        int nextIdx = i + 1;
        // 도로명 '시민대로 327번길 11' 또는 '테헤란로 14길 5' 보존
        if (isRoad && nextIdx < tokens.length) {
          final maybeBranch = tokens[nextIdx];
          if (RegExp(r'^\d+(?:번길|길)$').hasMatch(maybeBranch)) {
            roadSubBranch = maybeBranch;
            nextIdx++;
          }
        }
        if (nextIdx < tokens.length) {
          final nextToken = tokens[nextIdx];
          if (RegExp(r'^\d+(?:-\d+)?(?:번지|호)?$').hasMatch(nextToken)) {
            numberAfterUnit = nextToken.replaceAll(RegExp(r'(?:번지|호)$'), '');
          }
        }
        break;
      }
    }

    if (foundUnit) {
      final unitOnly = unitTokens.join(' ');
      if (roadSubBranch != null && numberAfterUnit != null) {
        addCandidate('$unitOnly $roadSubBranch $numberAfterUnit');
      }
      if (roadSubBranch != null) {
        addCandidate('$unitOnly $roadSubBranch');
      }
      if (numberAfterUnit != null) {
        addCandidate('$unitOnly $numberAfterUnit');
      }
      addCandidate(unitOnly);
    }

    // 3. 핵심 후보에 국가명('대한민국 ') 접두어 보강 (후보 과다로 인한 저장 지연 방지를 위해 상위 3개 핵심 후보에만 적용)
    final baseSnapshot = candidates.take(3).toList();
    for (final c in baseSnapshot) {
      if (!c.startsWith('대한민국')) {
        addCandidate('대한민국 $c');
      }
    }

    return candidates.take(6).toList();
  }

  static Future<void> _ensureKoreanLocale() async {
    if (_localeInitialized) return;
    _localeInitialized = true;
    try {
      await setLocaleIdentifier('ko_KR').timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// 상세 주소로 좌표 변환을 시도하고, 실패 시 정제·띄어쓰기 보정·번지/도로명·동 단위·대한민국 접두어·로컬 주소 DB 보완 순으로 재시도합니다.
  /// 대한민국 영토 내의 좌표가 아니면 null을 반환합니다.
  static Future<Location?> getCoordinateFromAddressFallback(String address) async {
    final addr = address.trim();
    if (addr.isEmpty) return null;

    await _ensureKoreanLocale();

    final candidates = buildGeocodeCandidates(addr);
    for (final candidate in candidates) {
      try {
        final List<Location> locations = await locationFromAddress(candidate)
            .timeout(const Duration(seconds: 4));
        for (final loc in locations) {
          if (_isValidSouthKorea(loc)) {
            if (candidate != addr) {
              debugPrint('폴백 좌표 변환 성공 (주소: $candidate)');
            }
            return loc;
          }
        }
      } catch (e) {
        debugPrint('좌표 변환 실패 (주소: $candidate): $e');
      }
    }

    // 4. 최후 폴백: 광역 시/도 없이 짧게 입력한 주소(예: '백석동', '역삼동 123')를 로컬 address.db(수도권 우선)로 보완
    final normalized = _spaceKoreanAdminTokens(normalizeAddressForGeocode(addr));
    if (normalized.isNotEmpty && !_sidoPrefixRe.hasMatch(normalized)) {
      try {
        final tokens = normalized.split(RegExp(r'\s+'));
        final dongToken = tokens.firstWhere(
          (t) => RegExp(r'^[가-힣]{1,6}(?:동|읍|면|리|가)$').hasMatch(t),
          orElse: () => tokens.first,
        );
        final dbMatches = await AddressRepository().search(dongToken);
        for (final fullName in dbMatches.take(2)) {
          final query = '대한민국 $fullName';
          try {
            final locs = await locationFromAddress(query)
                .timeout(const Duration(seconds: 6));
            for (final loc in locs) {
              if (_isValidSouthKorea(loc)) {
                debugPrint('로컬 주소DB 보완 좌표 변환 성공 ($addr → $fullName)');
                return loc;
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    return null;
  }
}

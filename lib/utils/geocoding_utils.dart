import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

import 'address_normalize.dart';

class GeocodingUtils {
  /// 대한민국 영토 바운더리 체크 (위도 33.1~38.6, 경도 124.6~132.0)
  static bool _isValidSouthKorea(Location loc) {
    return loc.latitude >= 33.1 &&
           loc.latitude <= 38.6 &&
           loc.longitude >= 124.6 &&
           loc.longitude <= 132.0;
  }

  /// 상세 주소로 좌표 변환을 시도하고, 실패 시 정제 주소 → 번지/도로번호 포함 → '동/읍/면/길/로' 순으로 재시도합니다.
  /// 대한민국 영토 내의 좌표가 아니면 null을 반환합니다.
  static Future<Location?> getCoordinateFromAddressFallback(String address) async {
    final addr = address.trim();
    if (addr.isEmpty) return null;

    final normalized = normalizeAddressForGeocode(addr);
    final base = normalized.isNotEmpty ? normalized : addr;

    final candidates = <String>[];
    void addCandidate(String s) {
      final t = s.trim();
      if (t.isNotEmpty && !candidates.contains(t)) {
        candidates.add(t);
      }
    }

    addCandidate(base);
    addCandidate(addr);

    final tokens = base.split(RegExp(r'\s+'));
    final List<String> fallbackTokens = [];
    String? numberAfterUnit;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      fallbackTokens.add(t);
      if (t.endsWith('동') ||
          t.endsWith('읍') ||
          t.endsWith('면') ||
          t.endsWith('리') ||
          t.endsWith('가') ||
          t.endsWith('길') ||
          t.endsWith('로')) {
        if (i + 1 < tokens.length) {
          final nextToken = tokens[i + 1];
          if (RegExp(r'^\d+(?:-\d+)?(?:번지|호)?$').hasMatch(nextToken)) {
            numberAfterUnit = nextToken;
          }
        }
        break;
      }
    }

    final unitOnlyAddress = fallbackTokens.join(' ');
    if (numberAfterUnit != null) {
      addCandidate('$unitOnlyAddress $numberAfterUnit');
    }
    addCandidate(unitOnlyAddress);

    for (final candidate in candidates) {
      try {
        final List<Location> locations = await locationFromAddress(candidate)
            .timeout(const Duration(seconds: 8));
        for (final loc in locations) {
          if (_isValidSouthKorea(loc)) {
            if (candidate != base) {
              debugPrint('폴백 좌표 변환 성공 (주소: $candidate)');
            }
            return loc;
          }
        }
      } catch (e) {
        debugPrint('좌표 변환 실패 (주소: $candidate): $e');
      }
    }

    return null;
  }
}

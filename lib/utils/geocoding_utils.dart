import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

class GeocodingUtils {
  /// 대한민국 영토 바운더리 체크 (위도 33.1~38.6, 경도 124.6~132.0)
  static bool _isValidSouthKorea(Location loc) {
    return loc.latitude >= 33.1 &&
           loc.latitude <= 38.6 &&
           loc.longitude >= 124.6 &&
           loc.longitude <= 132.0;
  }

  /// 상세 주소로 좌표 변환을 시도하고, 실패 시 '동/읍/면/길/로'까지만 추출하여 재시도합니다.
  /// 대한민국 영토 내의 좌표가 아니면 null을 반환합니다.
  static Future<Location?> getCoordinateFromAddressFallback(String address) async {
    final addr = address.trim();
    if (addr.isEmpty) return null;

    try {
      // 1. 원본 주소로 1차 시도
      final List<Location> locations = await locationFromAddress(addr);
      for (final loc in locations) {
        if (_isValidSouthKorea(loc)) {
          return loc;
        }
      }
    } catch (e) {
      debugPrint('1차 좌표 변환 실패 (주소: $addr): $e');
    }

    // 2. 실패 시 '동/읍/면/길/로'까지만 추출하여 2차 시도 (Fallback)
    final tokens = addr.split(RegExp(r'\s+'));
    final List<String> fallbackTokens = [];
    
    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      fallbackTokens.add(t);
      if (t.endsWith('동') || t.endsWith('읍') || t.endsWith('면') || t.endsWith('길') || t.endsWith('로')) {
        // '동/읍/면/길/로'를 찾으면 그 뒤의 상세주소(번지 수 등)는 무시
        break;
      }
    }

    final fallbackAddress = fallbackTokens.join(' ');
    if (fallbackAddress == addr) {
      // 추출된 주소가 원본과 동일하면 더 이상 시도할 의미가 없음
      return null;
    }

    try {
      final List<Location> locations = await locationFromAddress(fallbackAddress);
      for (final loc in locations) {
        if (_isValidSouthKorea(loc)) {
          debugPrint('2차 좌표 변환 성공 (주소: $fallbackAddress)');
          return loc;
        }
      }
    } catch (e) {
      debugPrint('2차 좌표 변환 실패 (주소: $fallbackAddress): $e');
    }

    return null;
  }
}

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

class GeocodingUtils {
  /// 상세 주소로 좌표 변환을 시도하고, 실패 시 "동/읍/면"을 추출하여 재시도합니다.
  static Future<Location?> getCoordinateFromAddressFallback(String address) async {
    final addr = address.trim();
    if (addr.isEmpty) return null;

    try {
      // 1. 원본 주소로 1차 시도
      final List<Location> locations = await locationFromAddress(addr);
      if (locations.isNotEmpty) {
        return locations.first;
      }
    } catch (e) {
      debugPrint('1차 좌표 변환 실패 (주소: $addr): $e');
    }

    // 2. 실패 시 "동/읍/면"만 추출하여 2차 시도 (Fallback)
    // 예: "서울 마포구 상수동 123-45" -> "서울 마포구 상수동" 또는 "상수동"
    // 여기서는 공백으로 분리한 후 "동", "읍", "면"으로 끝나는 단어를 찾습니다.
    final tokens = addr.split(RegExp(r'\s+'));
    final List<String> fallbackTokens = [];
    
    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      fallbackTokens.add(t);
      if (t.endsWith('동') || t.endsWith('읍') || t.endsWith('면')) {
        // "동/읍/면"을 찾으면 그 뒤의 상세주소(번지 등)는 무시
        break;
      }
    }

    final fallbackAddress = fallbackTokens.join(' ');
    if (fallbackAddress == addr) {
      // 추출한 주소가 원본과 동일하면 더 이상 시도할 의미가 없음
      return null;
    }

    try {
      final List<Location> locations = await locationFromAddress(fallbackAddress);
      if (locations.isNotEmpty) {
        debugPrint('2차 좌표 변환 성공 (주소: $fallbackAddress)');
        return locations.first;
      }
    } catch (e) {
      debugPrint('2차 좌표 변환 실패 (주소: $fallbackAddress): $e');
    }

    return null;
  }
}

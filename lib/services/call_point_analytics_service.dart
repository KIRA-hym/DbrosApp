import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum CallTimeSlotFilter { all, evening, peak, late, day }

enum CallFareFilter { all, over30k, over50k }

enum CallColorMode { fare, platform }

/// 내 위치 기준 반경 필터 (`3km / 5km / 10km / 전체`)
enum CallRadiusFilter { km3, km5, km10, all }

extension CallRadiusFilterExt on CallRadiusFilter {
  double? get maxKm {
    switch (this) {
      case CallRadiusFilter.km3:
        return 3.0;
      case CallRadiusFilter.km5:
        return 5.0;
      case CallRadiusFilter.km10:
        return 10.0;
      case CallRadiusFilter.all:
        return null;
    }
  }

  String get label {
    switch (this) {
      case CallRadiusFilter.km3:
        return '3km';
      case CallRadiusFilter.km5:
        return '5km';
      case CallRadiusFilter.km10:
        return '10km';
      case CallRadiusFilter.all:
        return '전체';
    }
  }

  CallRadiusFilter get next {
    switch (this) {
      case CallRadiusFilter.km3:
        return CallRadiusFilter.km5;
      case CallRadiusFilter.km5:
        return CallRadiusFilter.km10;
      case CallRadiusFilter.km10:
        return CallRadiusFilter.all;
      case CallRadiusFilter.all:
        return CallRadiusFilter.km3;
    }
  }
}

class AnalyticsCallPoint {
  final double lat;
  final double lng;
  final String startLocation;
  final String endLocation;
  final String programName;
  final int fare;
  final String rawTime;
  final String rawDriveTime;
  final int? callHour;
  final String regionName;
  final String displayDateTime;

  const AnalyticsCallPoint({
    required this.lat,
    required this.lng,
    required this.startLocation,
    required this.endLocation,
    required this.programName,
    required this.fare,
    required this.rawTime,
    required this.rawDriveTime,
    required this.callHour,
    required this.regionName,
    required this.displayDateTime,
  });

  factory AnalyticsCallPoint.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (json['lng'] as num?)?.toDouble() ?? 0.0;
    final sl = (json['sl']?.toString() ?? '').trim();
    final el = (json['el']?.toString() ?? '').trim();
    final prog =
        ((json['program'] ?? json['t'])?.toString() ?? '기타').trim();
    final fareRaw = json['f'];
    final fare = fareRaw is num
        ? fareRaw.toInt()
        : (int.tryParse(fareRaw?.toString() ?? '0') ?? 0);
    final rawTime = (json['time']?.toString() ?? '').trim();
    final rawDt = (json['dt']?.toString() ?? '').trim();

    return AnalyticsCallPoint(
      lat: lat,
      lng: lng,
      startLocation: sl.isEmpty ? '출발지 정보 없음' : sl,
      endLocation: el.isEmpty ? '도착지 정보 없음' : el,
      programName: prog.isEmpty ? '기타' : prog,
      fare: fare,
      rawTime: rawTime,
      rawDriveTime: rawDt,
      callHour: CallPointAnalyticsService.extractCallHour(rawDt, rawTime),
      regionName: CallPointAnalyticsService.extractRegionName(sl),
      displayDateTime:
          CallPointAnalyticsService.formatDisplayDateTime(rawDt, rawTime),
    );
  }
}

class CallPointDataset {
  final String updatedAtIso;
  final List<AnalyticsCallPoint> points;
  final bool fromCache;

  const CallPointDataset({
    required this.updatedAtIso,
    required this.points,
    this.fromCache = false,
  });
}

class RegionHotspotStat {
  final String region;
  final int count;
  final int avgFare;
  final int maxFare;
  final double centerLat;
  final double centerLng;
  final String mainHour;

  const RegionHotspotStat({
    required this.region,
    required this.count,
    required this.avgFare,
    required this.maxFare,
    required this.centerLat,
    required this.centerLng,
    required this.mainHour,
  });
}

class HourBucketStat {
  final int hour;
  final int count;
  final int avgFare;

  const HourBucketStat({
    required this.hour,
    required this.count,
    required this.avgFare,
  });
}

class PlatformBreakdownStat {
  final String key;
  final String name;
  final int count;
  final int ratio;
  final int avgFare;
  final int colorValue;

  const PlatformBreakdownStat({
    required this.key,
    required this.name,
    required this.count,
    required this.ratio,
    required this.avgFare,
    required this.colorValue,
  });
}

class CallPointAnalyticsResult {
  final List<AnalyticsCallPoint> filteredPoints;
  final int totalRawCount;
  final int filteredCount;
  final int avgFare;
  final int maxFare;
  final int high30kCount;
  final int high50kCount;
  final int high30kRatio;
  final HourBucketStat? peakHour;
  final List<HourBucketStat> orderedHourBuckets;
  final List<RegionHotspotStat> regionRankings;
  final List<PlatformBreakdownStat> platformBreakdown;

  const CallPointAnalyticsResult({
    required this.filteredPoints,
    required this.totalRawCount,
    required this.filteredCount,
    required this.avgFare,
    required this.maxFare,
    required this.high30kCount,
    required this.high50kCount,
    required this.high30kRatio,
    required this.peakHour,
    required this.orderedHourBuckets,
    required this.regionRankings,
    required this.platformBreakdown,
  });
}

class CallPointAnalyticsService {
  CallPointAnalyticsService._();

  static const String _endpointUrl =
      'https://us-central1-dbros-apps-7bbmw4.cloudfunctions.net/getCallPointsMap';
  static const String _cacheFileName = 'call_points_analytics_cache.json';
  static const Duration _cacheTtl = Duration(hours: 6);

  static CallPointDataset? _memoryCache;
  static DateTime? _memoryCachedAt;

  /// 주요 시간대 표시 순서 (18시~23시 -> 00시~05시 -> 주간)
  static const List<int> orderedHours = <int>[
    18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
    15, 16, 17,
  ];

  /// 서버 공유 콜포인트 빅데이터 로드 (메모리 → 디스크 캐시 → 네트워크)
  static Future<CallPointDataset> loadDataset({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _memoryCache != null &&
        _memoryCachedAt != null &&
        DateTime.now().difference(_memoryCachedAt!) < _cacheTtl) {
      return _memoryCache!;
    }

    File? cacheFile;
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        cacheFile = File('${dir.path}/$_cacheFileName');
        if (!forceRefresh && await cacheFile.exists()) {
          final modified = await cacheFile.lastModified();
          if (DateTime.now().difference(modified) < _cacheTtl) {
            final raw = await cacheFile.readAsString();
            final parsed = parsePayload(raw, fromCache: true);
            if (parsed.points.isNotEmpty) {
              _memoryCache = parsed;
              _memoryCachedAt = DateTime.now();
              return parsed;
            }
          }
        }
      } catch (e) {
        debugPrint('[CallPointAnalytics] 캐시 읽기 실패: $e');
      }
    }

    try {
      final uri = Uri.parse(
        '$_endpointUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final body = utf8.decode(resp.bodyBytes);
        final dataset = parsePayload(body, fromCache: false);
        _memoryCache = dataset;
        _memoryCachedAt = DateTime.now();
        if (cacheFile != null) {
          try {
            await cacheFile.writeAsString(body);
          } catch (_) {}
        }
        return dataset;
      }
    } catch (e) {
      debugPrint('[CallPointAnalytics] 네트워크 조회 실패: $e');
    }

    // 네트워크 실패 시 만료된 디스크 캐시라도 폴백 사용
    if (cacheFile != null && await cacheFile.exists()) {
      try {
        final raw = await cacheFile.readAsString();
        final parsed = parsePayload(raw, fromCache: true);
        _memoryCache = parsed;
        _memoryCachedAt = DateTime.now();
        return parsed;
      } catch (_) {}
    }

    if (_memoryCache != null) return _memoryCache!;
    throw Exception('콜포인트 분석 데이터를 불러오지 못했습니다. 네트워크 연결을 확인해 주세요.');
  }

  /// JSON 문자열 파싱 (`public/call_points_map.json` 포맷)
  static CallPointDataset parsePayload(
    String rawJson, {
    bool fromCache = false,
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return CallPointDataset(
        updatedAtIso: '',
        points: const [],
        fromCache: fromCache,
      );
    }
    final updatedAt = decoded['updatedAtISO']?.toString() ?? '';
    final rawList = decoded['points'];
    final List<AnalyticsCallPoint> points = [];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final pt = AnalyticsCallPoint.fromJson(item);
          if (pt.lat != 0.0 && pt.lng != 0.0) {
            points.add(pt);
          }
        }
      }
    }
    return CallPointDataset(
      updatedAtIso: updatedAt,
      points: points,
      fromCache: fromCache,
    );
  }

  /// 운행시간(시:분) 또는 ISO 타임스탬프에서 시간(0~23) 추출
  static int? extractCallHour(String? dt, String? timeIso) {
    final dtTrim = (dt ?? '').trim();
    if (dtTrim.contains(':')) {
      final h = int.tryParse(dtTrim.split(':').first.trim());
      if (h != null && h >= 0 && h < 24) return h;
    }
    final tTrim = (timeIso ?? '').trim();
    if (tTrim.isNotEmpty) {
      final parsed = DateTime.tryParse(tTrim)?.toLocal();
      if (parsed != null) return parsed.hour;
    }
    return null;
  }

  /// 주소에서 행정동/읍/면/가/역/CC 추출 (DbrosAdmin 동일 로직)
  static String extractRegionName(String sl) {
    final clean = sl.trim();
    if (clean.isEmpty || clean == '출발지 정보 없음') return '기타 지역';
    final match = RegExp(r'([가-힣0-9]+(?:동|읍|면|가|역|CC))').firstMatch(clean);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
    final first = clean.split(RegExp(r'\s+')).first;
    return first.isEmpty ? '기타 지역' : first;
  }

  /// 표기 통일: `YY.MM.DD HH:mm` (예: `26.11.20 13:15`)
  static String formatDisplayDateTime(String? dt, String? timeIso) {
    final dtTrim = (dt ?? '').trim();
    String? normTime;
    final tm = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(dtTrim);
    if (tm != null) {
      normTime = '${tm.group(1)!.padLeft(2, '0')}:${tm.group(2)!}';
    }

    final tTrim = (timeIso ?? '').trim();
    if (tTrim.isNotEmpty) {
      final parsed = DateTime.tryParse(tTrim)?.toLocal();
      if (parsed != null) {
        final yy = (parsed.year % 100).toString().padLeft(2, '0');
        final mo = parsed.month.toString().padLeft(2, '0');
        final dd = parsed.day.toString().padLeft(2, '0');
        final tp = normTime ??
            '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
        return '$yy.$mo.$dd $tp';
      }
    }
    return normTime ?? '';
  }

  /// 시간대 슬롯 매칭
  static bool matchesTimeSlot(
    int? hour,
    CallTimeSlotFilter slot,
    int? exactHour,
  ) {
    if (exactHour != null) return hour == exactHour;
    if (slot == CallTimeSlotFilter.all) return true;
    if (hour == null) return false;
    switch (slot) {
      case CallTimeSlotFilter.all:
        return true;
      case CallTimeSlotFilter.evening:
        return hour >= 18 && hour < 21;
      case CallTimeSlotFilter.peak:
        return hour >= 21 || hour == 0;
      case CallTimeSlotFilter.late:
        return hour >= 1 && hour < 5;
      case CallTimeSlotFilter.day:
        return hour >= 5 && hour < 18;
    }
  }

  /// Haversine 거리 계산 (km)
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// 플랫폼별 대표 컬러값
  static int platformColorValue(String prog) {
    if (prog.contains('카카오')) return 0xFFEAB308;
    if (prog.contains('로지')) return 0xFF22C55E;
    if (prog.contains('콜마너')) return 0xFFA855F7;
    if (prog.contains('티맵')) return 0xFF3B82F6;
    if (prog.contains('핸들')) return 0xFFE5E7EB;
    return 0xFF9CA3AF;
  }

  /// 단가별 히트 컬러값
  static int fareColorValue(int fare) {
    if (fare >= 50000) return 0xFFEF4444;
    if (fare >= 30000) return 0xFFF59E0B;
    return 0xFF3B82F6;
  }

  /// 필터링 및 전체 KPI / 핫스팟 / 시간대 / 플랫폼 집계 계산
  static CallPointAnalyticsResult computeAnalytics({
    required List<AnalyticsCallPoint> allPoints,
    required CallTimeSlotFilter timeSlot,
    int? exactHour,
    required CallFareFilter fareFilter,
    required String platformFilter,
    required CallRadiusFilter radiusFilter,
    double? userLat,
    double? userLng,
    String? selectedRegion,
    String searchQuery = '',
    bool sortRegionByFare = false,
  }) {
    final maxKm = radiusFilter.maxKm;
    final hasUserLoc = userLat != null && userLng != null;
    final queryLower = searchQuery.trim().toLowerCase();

    bool passesBaseFilter(AnalyticsCallPoint pt) {
      if (!matchesTimeSlot(pt.callHour, timeSlot, exactHour)) return false;
      if (fareFilter == CallFareFilter.over30k && pt.fare < 30000) return false;
      if (fareFilter == CallFareFilter.over50k && pt.fare < 50000) return false;
      if (platformFilter != 'all' && !pt.programName.contains(platformFilter)) {
        return false;
      }
      if (maxKm != null && hasUserLoc) {
        if (distanceKm(userLat, userLng, pt.lat, pt.lng) > maxKm) {
          return false;
        }
      }
      if (queryLower.isNotEmpty) {
        final inSl = pt.startLocation.toLowerCase().contains(queryLower);
        final inEl = pt.endLocation.toLowerCase().contains(queryLower);
        final inProg = pt.programName.toLowerCase().contains(queryLower);
        if (!inSl && !inEl && !inProg) return false;
      }
      return true;
    }

    final List<AnalyticsCallPoint> baseFiltered = [];
    final List<AnalyticsCallPoint> filtered = [];

    for (final pt in allPoints) {
      if (!passesBaseFilter(pt)) continue;
      baseFiltered.add(pt);
      if (selectedRegion == null || pt.regionName == selectedRegion) {
        filtered.add(pt);
      }
    }

    // 1. KPI 계산
    int validFareCount = 0;
    int totalFare = 0;
    int maxFare = 0;
    int high30k = 0;
    int high50k = 0;

    final List<int> hourCount = List<int>.filled(24, 0);
    final List<int> hourSumFare = List<int>.filled(24, 0);

    for (final pt in filtered) {
      if (pt.fare > 0) {
        validFareCount++;
        totalFare += pt.fare;
        if (pt.fare > maxFare) maxFare = pt.fare;
        if (pt.fare >= 30000) high30k++;
        if (pt.fare >= 50000) high50k++;
      }
      final h = pt.callHour;
      if (h != null && h >= 0 && h < 24) {
        hourCount[h]++;
        hourSumFare[h] += pt.fare;
      }
    }

    final int avgFare =
        validFareCount > 0 ? (totalFare / validFareCount).round() : 0;
    final int high30kRatio = filtered.isNotEmpty
        ? ((high30k / filtered.length) * 100).round()
        : 0;

    final List<HourBucketStat> orderedBuckets = [];
    HourBucketStat? peak;
    for (final h in orderedHours) {
      final c = hourCount[h];
      if (c > 0) {
        final bucket = HourBucketStat(
          hour: h,
          count: c,
          avgFare: (hourSumFare[h] / c).round(),
        );
        orderedBuckets.add(bucket);
        if (peak == null || bucket.count > peak.count) {
          peak = bucket;
        }
      }
    }

    // 2. 지역별 핫스팟 TOP 15 (selectedRegion 제외 baseFiltered 기준)
    final Map<String, _RegionAcc> regionAcc = {};
    for (final pt in baseFiltered) {
      if (pt.regionName == '기타 지역') continue;
      final acc = regionAcc.putIfAbsent(pt.regionName, () => _RegionAcc());
      acc.count++;
      acc.sumFare += pt.fare;
      if (pt.fare > acc.maxFare) acc.maxFare = pt.fare;
      acc.sumLat += pt.lat;
      acc.sumLng += pt.lng;
      if (pt.callHour != null) {
        acc.hours[pt.callHour!] = (acc.hours[pt.callHour!] ?? 0) + 1;
      }
    }

    List<RegionHotspotStat> rankings = regionAcc.entries.map((entry) {
      final a = entry.value;
      int? topH;
      int topHCnt = -1;
      a.hours.forEach((h, c) {
        if (c > topHCnt) {
          topHCnt = c;
          topH = h;
        }
      });
      return RegionHotspotStat(
        region: entry.key,
        count: a.count,
        avgFare: a.count > 0 ? (a.sumFare / a.count).round() : 0,
        maxFare: a.maxFare,
        centerLat: a.sumLat / a.count,
        centerLng: a.sumLng / a.count,
        mainHour: topH != null ? '${topH.toString().padLeft(2, '0')}시' : '-',
      );
    }).toList();

    if (sortRegionByFare) {
      final multi = rankings.where((r) => r.count >= 2).toList();
      if (multi.isNotEmpty) rankings = multi;
      rankings.sort((a, b) {
        final cmp = b.avgFare.compareTo(a.avgFare);
        return cmp != 0 ? cmp : b.count.compareTo(a.count);
      });
    } else {
      rankings.sort((a, b) {
        final cmp = b.count.compareTo(a.count);
        return cmp != 0 ? cmp : b.avgFare.compareTo(a.avgFare);
      });
    }
    if (rankings.length > 15) {
      rankings = rankings.sublist(0, 15);
    }

    // 3. 플랫폼별 비중 & 평균 단가
    const groups = [
      ('카카오', '카카오', 0xFFEAB308),
      ('로지', '로지', 0xFF22C55E),
      ('콜마너', '콜마너', 0xFFA855F7),
      ('티맵', '티맵', 0xFF3B82F6),
      ('핸들', '핸들포유', 0xFFE5E7EB),
    ];
    final List<PlatformBreakdownStat> breakdown = [];
    for (final g in groups) {
      int cnt = 0;
      int sum = 0;
      for (final pt in filtered) {
        if (pt.programName.contains(g.$1)) {
          cnt++;
          sum += pt.fare;
        }
      }
      if (cnt > 0) {
        breakdown.add(PlatformBreakdownStat(
          key: g.$1,
          name: g.$2,
          count: cnt,
          ratio: filtered.isNotEmpty ? ((cnt / filtered.length) * 100).round() : 0,
          avgFare: (sum / cnt).round(),
          colorValue: g.$3,
        ));
      }
    }

    return CallPointAnalyticsResult(
      filteredPoints: filtered,
      totalRawCount: allPoints.length,
      filteredCount: filtered.length,
      avgFare: avgFare,
      maxFare: maxFare,
      high30kCount: high30k,
      high50kCount: high50k,
      high30kRatio: high30kRatio,
      peakHour: peak,
      orderedHourBuckets: orderedBuckets,
      regionRankings: rankings,
      platformBreakdown: breakdown,
    );
  }
}

class _RegionAcc {
  int count = 0;
  int sumFare = 0;
  int maxFare = 0;
  double sumLat = 0;
  double sumLng = 0;
  final Map<int, int> hours = {};
}

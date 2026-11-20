import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/services/call_point_analytics_service.dart';

void main() {
  final samplePayload = jsonEncode({
    'updatedAtISO': '2026-11-20T06:00:00.000Z',
    'points': [
      {
        'lat': 37.5006,
        'lng': 127.0365,
        'sl': '서울 강남구 역삼동 721-12',
        'el': '경기 성남시 분당구 판교동',
        'program': '카카오(프콜)',
        'f': 58000,
        'dt': '23:15',
        'time': '2026-11-20T14:15:00.000Z',
      },
      {
        'lat': 37.5020,
        'lng': 127.0400,
        'sl': '서울 강남구 역삼동 테헤란로',
        'el': '서울 송파구 잠실동',
        'program': '로지',
        'f': 32000,
        'dt': '22:40',
        'time': '2026-11-20T13:40:00.000Z',
      },
      {
        'lat': 37.5350,
        'lng': 127.0800,
        'sl': '서울 광진구 구의동 100',
        'el': '경기 하남시 신장동',
        'program': '콜마너',
        'f': 25000,
        'dt': '19:30',
        'time': '2026-11-20T10:30:00.000Z',
      },
      {
        'lat': 37.3947,
        'lng': 127.1112,
        'sl': '경기 성남시 분당구 백현동 판교역',
        'el': '서울 서초구 방배동',
        'program': '티맵',
        'f': 52000,
        'dt': '01:20',
        'time': '2026-11-20T16:20:00.000Z',
      },
    ],
  });

  group('CallPointAnalyticsService', () {
    test('JSON 파싱, 지역명 추출, YY.MM.DD HH:mm 포맷 확인', () {
      final ds = CallPointAnalyticsService.parsePayload(samplePayload);
      expect(ds.points.length, 4);
      expect(ds.points[0].regionName, '역삼동');
      expect(ds.points[0].callHour, 23);
      expect(ds.points[0].displayDateTime, '26.11.20 23:15');
      expect(ds.points[3].regionName, '백현동');
    });

    test('내 위치 기준 3km / 5km / 10km / 전체 반경 필터링', () {
      final ds = CallPointAnalyticsService.parsePayload(samplePayload);
      // 기준점: 역삼동 (37.5006, 127.0365)
      final r3 = CallPointAnalyticsService.computeAnalytics(
        allPoints: ds.points,
        timeSlot: CallTimeSlotFilter.all,
        fareFilter: CallFareFilter.all,
        platformFilter: 'all',
        radiusFilter: CallRadiusFilter.km3,
        userLat: 37.5006,
        userLng: 127.0365,
      );
      expect(r3.filteredCount, 2); // 역삼동 2건만 (3km 이내)

      final r10 = CallPointAnalyticsService.computeAnalytics(
        allPoints: ds.points,
        timeSlot: CallTimeSlotFilter.all,
        fareFilter: CallFareFilter.all,
        platformFilter: 'all',
        radiusFilter: CallRadiusFilter.km10,
        userLat: 37.5006,
        userLng: 127.0365,
      );
      expect(r10.filteredCount, 3); // 역삼동 2건 + 구의동(약 5.4km)

      final rAll = CallPointAnalyticsService.computeAnalytics(
        allPoints: ds.points,
        timeSlot: CallTimeSlotFilter.all,
        fareFilter: CallFareFilter.all,
        platformFilter: 'all',
        radiusFilter: CallRadiusFilter.all,
        userLat: 37.5006,
        userLng: 127.0365,
      );
      expect(rAll.filteredCount, 4); // 판교(약 13.5km)까지 포함
    });

    test('시간대(야간피크)·단가(5만↑)·KPI·핫스팟·플랫폼 집계 검증', () {
      final ds = CallPointAnalyticsService.parsePayload(samplePayload);

      final allStats = CallPointAnalyticsService.computeAnalytics(
        allPoints: ds.points,
        timeSlot: CallTimeSlotFilter.all,
        fareFilter: CallFareFilter.all,
        platformFilter: 'all',
        radiusFilter: CallRadiusFilter.all,
      );
      expect(allStats.avgFare, ((58000 + 32000 + 25000 + 52000) / 4).round());
      expect(allStats.maxFare, 58000);
      expect(allStats.high30kCount, 3);
      expect(allStats.high50kCount, 2);
      expect(allStats.high30kRatio, 75);
      expect(allStats.regionRankings.first.region, '역삼동');
      expect(allStats.regionRankings.first.count, 2);
      expect(allStats.platformBreakdown.length, 4);

      final peak50k = CallPointAnalyticsService.computeAnalytics(
        allPoints: ds.points,
        timeSlot: CallTimeSlotFilter.peak,
        fareFilter: CallFareFilter.over50k,
        platformFilter: 'all',
        radiusFilter: CallRadiusFilter.all,
      );
      expect(peak50k.filteredCount, 1);
      expect(peak50k.filteredPoints.first.programName, '카카오(프콜)');
    });

    test('반경 순환 순서 확인: 3km -> 5km -> 10km -> 전체 -> 3km', () {
      expect(CallRadiusFilter.km3.next, CallRadiusFilter.km5);
      expect(CallRadiusFilter.km5.next, CallRadiusFilter.km10);
      expect(CallRadiusFilter.km10.next, CallRadiusFilter.all);
      expect(CallRadiusFilter.all.next, CallRadiusFilter.km3);
    });
  });
}

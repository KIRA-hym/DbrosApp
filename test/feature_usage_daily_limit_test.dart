import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbros_app/services/feature_usage_service.dart';
import 'package:dbros_app/services/settings_service.dart';
import 'package:dbros_app/services/trusted_clock_service.dart';
import 'package:dbros_app/utils/work_date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> resetPrefs([Map<String, Object> initial = const {}]) async {
    TrustedClockService.resetForTest();
    SharedPreferences.setMockInitialValues(initial);
    await TrustedClockService.init();
    TrustedClockService.setServerAnchorForTest(
      DateTime.now().millisecondsSinceEpoch,
    );
    await SettingsService.init();
    await FeatureUsageService.init();
  }

  tearDown(() {
    TrustedClockService.resetForTest();
  });

  group('auto_screenshot / status_bar 1일 1회(2시간) 광고 체험 제한', () {
    test('auto_screenshot: 오늘 첫 광고 시청 시 2시간 해제, 같은 날 재시도 차단', () async {
      await resetPrefs();

      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isTrue);
      expect(await FeatureUsageService.canUseTimedAdPassToday('auto_screenshot'), isTrue);
      expect(SettingsService.isFeatureUnlocked('auto_screenshot'), isFalse);

      // 1회차 광고 보상 지급 성공
      final firstGranted = await FeatureUsageService.grantTimedPass(
        'auto_screenshot',
        const Duration(hours: 2),
      );
      expect(firstGranted, isTrue);
      expect(SettingsService.isFeatureUnlocked('auto_screenshot'), isTrue);
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isFalse);
      expect(await FeatureUsageService.canUseTimedAdPassToday('auto_screenshot'), isFalse);

      // 2시간 경과(만료) 시뮬레이션
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'auto_screenshot_unlock_until_ms',
        DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
      await SettingsService.reload();

      expect(SettingsService.isFeatureUnlocked('auto_screenshot'), isFalse);
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isFalse);

      // 같은 날 2회차 광고 보상 지급 차단
      final secondGranted = await FeatureUsageService.grantTimedPass(
        'auto_screenshot',
        const Duration(hours: 2),
      );
      expect(secondGranted, isFalse);
      expect(SettingsService.isFeatureUnlocked('auto_screenshot'), isFalse);
    });

    test('status_bar: 오늘 첫 광고 시청 시 2시간 해제, 만료 후 같은 날 재시도 차단', () async {
      await resetPrefs();

      expect(FeatureUsageService.canUseTimedAdPassTodaySync('status_bar'), isTrue);

      final firstGranted = await FeatureUsageService.grantTimedPass(
        'status_bar',
        const Duration(hours: 2),
      );
      expect(firstGranted, isTrue);
      expect(SettingsService.isFeatureUnlocked('status_bar'), isTrue);
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('status_bar'), isFalse);

      // 만료 시뮬레이션
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'status_bar_unlock_until_ms',
        DateTime.now().subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
      );
      await SettingsService.reload();
      expect(SettingsService.isFeatureUnlocked('status_bar'), isFalse);

      final secondGranted = await FeatureUsageService.grantTimedPass(
        'status_bar',
        const Duration(hours: 2),
      );
      expect(secondGranted, isFalse);
      expect(SettingsService.isFeatureUnlocked('status_bar'), isFalse);
    });

    test('다음 근무일(어제 날짜로 저장된 상태)이 되면 다시 1회 허용', () async {
      final today = WorkDateUtils.effectiveWorkDateYmd();
      final parts = today.split('-').map(int.parse).toList();
      final yesterdayDt = DateTime(parts[0], parts[1], parts[2]).subtract(const Duration(days: 1));
      final yesterday =
          '${yesterdayDt.year.toString().padLeft(4, '0')}-${yesterdayDt.month.toString().padLeft(2, '0')}-${yesterdayDt.day.toString().padLeft(2, '0')}';

      await resetPrefs({
        'auto_screenshot_date': yesterday,
        'auto_screenshot_ad_count': 1,
        'auto_screenshot_unlock_until_ms':
            DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
        'status_bar_date': yesterday,
        'status_bar_ad_count': 1,
        'status_bar_unlock_until_ms':
            DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
      });

      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isTrue);
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('status_bar'), isTrue);

      expect(
        await FeatureUsageService.grantTimedPass('auto_screenshot', const Duration(hours: 2)),
        isTrue,
      );
      expect(
        await FeatureUsageService.grantTimedPass('status_bar', const Duration(hours: 2)),
        isTrue,
      );
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isFalse);
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('status_bar'), isFalse);
    });

    test('overlay_quick은 1일 1회 제한 대상이 아니므로 재발급 가능', () async {
      await resetPrefs();

      expect(
        await FeatureUsageService.grantTimedPass('overlay_quick', const Duration(hours: 2)),
        isTrue,
      );
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('overlay_quick'), isTrue);
      expect(
        await FeatureUsageService.grantTimedPass('overlay_quick', const Duration(hours: 2)),
        isTrue,
      );
    });
  });

  group('기기 시계 조작 우회 방어 (TrustedClockService)', () {
    test('시계를 과거(어제)로 돌려도 1일 1회 광고 체험 카운터가 초기화되지 않는다', () async {
      DateTime fakeNow = DateTime(2026, 11, 23, 14, 0);
      await resetPrefs();
      TrustedClockService.nowOverride = () => fakeNow;

      // 오늘(2026-11-23) 1회 사용
      expect(
        await FeatureUsageService.grantTimedPass('auto_screenshot', const Duration(hours: 2)),
        isTrue,
      );
      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isFalse);

      // 기기 날짜를 어제(2026-11-22)로 되돌림
      fakeNow = DateTime(2026, 11, 22, 14, 0);

      expect(FeatureUsageService.canUseTimedAdPassTodaySync('auto_screenshot'), isFalse);
      expect(await FeatureUsageService.canUseTimedAdPassToday('auto_screenshot'), isFalse);
      expect(
        await FeatureUsageService.grantTimedPass('auto_screenshot', const Duration(hours: 2)),
        isFalse,
      );
    });

    test('시계를 과거로 돌려도 single_ocr 무료 2회 카운터가 초기화되지 않는다', () async {
      DateTime fakeNow = DateTime(2026, 11, 23, 14, 0);
      await resetPrefs();
      TrustedClockService.nowOverride = () => fakeNow;

      await FeatureUsageService.incrementFreeUsage('single_ocr');
      await FeatureUsageService.incrementFreeUsage('single_ocr');
      expect(await FeatureUsageService.canUseSingleOcrFree(), isFalse);

      // 어제로 날짜 변경 시도
      fakeNow = DateTime(2026, 11, 22, 14, 0);
      expect(await FeatureUsageService.canUseSingleOcrFree(), isFalse);

      // 실제 다음 근무일(2026-11-24 09:05)이 되면 정상 초기화
      fakeNow = DateTime(2026, 11, 24, 9, 5);
      expect(await FeatureUsageService.canUseSingleOcrFree(), isTrue);
    });

    test('오프라인 상태에서 High-Water Mark보다 과거로 시계가 되감기지 않는다', () async {
      final highWater = DateTime.now().add(const Duration(hours: 3)).millisecondsSinceEpoch;
      TrustedClockService.resetForTest();
      SharedPreferences.setMockInitialValues({
        'trusted_clock_high_water_ms': highWater,
      });
      await TrustedClockService.init();

      // 로컬 시각이 highWater보다 과거이므로 highWater 이상을 반환해야 함
      expect(TrustedClockService.nowMs(), greaterThanOrEqualTo(highWater));
    });

    test('서버 앵커 동기화 후 2시간 패스가 경과하면 정상 만료된다', () async {
      DateTime fakeNow = DateTime(2026, 11, 23, 14, 0);
      await resetPrefs();
      TrustedClockService.nowOverride = () => fakeNow;

      expect(
        await FeatureUsageService.grantTimedPass('status_bar', const Duration(hours: 2)),
        isTrue,
      );
      expect(SettingsService.isFeatureUnlocked('status_bar'), isTrue);

      // 2시간 1분 경과
      fakeNow = DateTime(2026, 11, 23, 16, 1);
      expect(SettingsService.isFeatureUnlocked('status_bar'), isFalse);
      expect(await FeatureUsageService.hasDailyPassAsync('status_bar'), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbros_app/services/feature_usage_service.dart';
import 'package:dbros_app/services/settings_service.dart';
import 'package:dbros_app/utils/work_date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> resetPrefs([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    await SettingsService.init();
    await FeatureUsageService.init();
  }

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
}

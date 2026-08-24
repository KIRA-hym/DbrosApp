import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class FeatureUsageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String get _todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());

  static Future<void> _checkAndResetDailyCounter(String featureKey) async {
    final lastDate = _prefs.getString('${featureKey}_date');
    if (lastDate != _todayKey) {
      await _prefs.setString('${featureKey}_date', _todayKey);
      await _prefs.setInt('${featureKey}_free_count', 0);
      await _prefs.setInt('${featureKey}_ad_count', 0);
    }
  }

  static Future<Map<String, int>> getUsageStats(String feature) async {
    await _checkAndResetDailyCounter(feature);
    final freeCount = _prefs.getInt('${feature}_free_count') ?? 0;
    final adCount = _prefs.getInt('${feature}_ad_count') ?? 0;
    return {'free': freeCount, 'ad': adCount};
  }

  static Future<void> incrementFreeUsage(String feature) async {
    await _checkAndResetDailyCounter(feature);
    final count = _prefs.getInt('${feature}_free_count') ?? 0;
    await _prefs.setInt('${feature}_free_count', count + 1);
  }

  static Future<void> incrementAdUsage(String feature) async {
    await _checkAndResetDailyCounter(feature);
    final count = _prefs.getInt('${feature}_ad_count') ?? 0;
    await _prefs.setInt('${feature}_ad_count', count + 1);
  }

  // Helper check functions
  
  static Future<bool> canUseSingleOcrFree() async {
    final stats = await getUsageStats('single_ocr');
    return stats['free']! < 2; // 2회 무료
  }

  static Future<bool> canUseSingleOcrWithAd() async {
    final stats = await getUsageStats('single_ocr');
    return stats['ad']! < 1; // 무료 2회 초과 시 광고보고 1회 (총 3회)
  }

  static Future<bool> canUseMultiOcrWithAd() async {
    final stats = await getUsageStats('multi_ocr');
    return stats['ad']! < 3; // 처음부터 광고보고 3회
  }

  static Future<bool> canUseCallMapFree() async {
    final stats = await getUsageStats('call_map');
    return stats['free']! < 1; // 1회 무료
  }

  static Future<bool> canUseCallMapWithAd() async {
    final stats = await getUsageStats('call_map');
    return stats['ad']! < 2; // 무료 초과시 광고보고 2회 (총 3회)
  }

  static Future<bool> canUseStatsWithAd() async {
    final stats = await getUsageStats('stats');
    return stats['ad']! < 3; // 들어갈때마다 광고, 하루 3회
  }
}

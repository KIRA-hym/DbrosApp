import 'package:shared_preferences/shared_preferences.dart';
import '../utils/work_date_utils.dart';

class FeatureUsageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String get _todayKey => WorkDateUtils.effectiveWorkDateYmd();

  static Future<void> _checkAndResetDailyCounter(String featureKey) async {
    final lastDate = _prefs.getString('${featureKey}_date');
    if (lastDate != _todayKey) {
      await _prefs.setString('${featureKey}_date', _todayKey);
      await _prefs.setInt('${featureKey}_free_count', 0);
      await _prefs.setInt('${featureKey}_ad_count', 0);
      await _prefs.setBool('${featureKey}_daily_pass', false);
    }
  }

  // --- Daily Pass Logic (오전 9시 일괄 초기화 무제한 패스) ---

  static Future<bool> hasDailyPassAsync(String featureKey) async {
    await _checkAndResetDailyCounter(featureKey);
    return _prefs.getBool('${featureKey}_daily_pass') ?? false;
  }

  static Future<void> grantDailyPass(String featureKey) async {
    await _checkAndResetDailyCounter(featureKey);
    await _prefs.setBool('${featureKey}_daily_pass', true);
    // 통계/로깅용으로 카운트도 증가
    final count = _prefs.getInt('${featureKey}_ad_count') ?? 0;
    await _prefs.setInt('${featureKey}_ad_count', count + 1);
  }

  // 동기(Synchronous) 읽기 - UI나 프로바이더에서 즉시 상태를 확인할 때 사용
  static bool hasDailyPassSync(String featureKey) {
    final lastDate = _prefs.getString('${featureKey}_date');
    if (lastDate != _todayKey) return false;
    return _prefs.getBool('${featureKey}_daily_pass') ?? false;
  }

  // --- 기존 횟수 차감제 로직 (무료 횟수 체크용으로 유지) ---

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
    await grantDailyPass(feature); // 기존 adUsage 증가를 pass 발급으로 통일
  }

  // Helper check functions

  static Future<bool> canUseSingleOcrFree() async {
    final stats = await getUsageStats('single_ocr');
    return stats['free']! < 2; // 2회 무료
  }

  static Future<bool> canUseSingleOcrWithAd() async {
    return true; // 프리패스 제도로 변경되었으므로 언제든 광고 시청 가능
  }

  static Future<bool> canUseMultiOcrWithAd() async {
    return true; // 프리패스 제도로 변경되었으므로 언제든 광고 시청 가능
  }

  static Future<bool> canUseCallMapFree() async {
    final stats = await getUsageStats('call_map');
    return stats['free']! < 1; // 1회 무료
  }

  static Future<bool> canUseRouteMapFree() async {
    final stats = await getUsageStats('route_map');
    return stats['free']! < 1; // 1회 무료
  }

  static Future<bool> canUseRouteMapWithAd() async {
    return true; // 프리패스 제도로 변경되었으므로 언제든 광고 시청 가능
  }

  static Future<bool> canUseCallMapWithAd() async {
    return true; // 프리패스 제도로 변경되었으므로 언제든 광고 시청 가능
  }

  static Future<bool> canUseStatsWithAd() async {
    return true; // 프리패스 제도로 변경되었으므로 언제든 광고 시청 가능
  }
}

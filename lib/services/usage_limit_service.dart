// GEMINI_HYBRID_PARSE_BEGIN
import 'package:shared_preferences/shared_preferences.dart';

/// Gemini API 일일 호출 상한(15건) — [checkAndIncrementUsage]로 원자적 소비.
class UsageLimitService {
  UsageLimitService._();
  static final UsageLimitService instance = UsageLimitService._();

  static const String _prefsKeyDate = 'gemini_hybrid_usage_date_ymd';
  static const String _prefsKeyCount = 'gemini_hybrid_usage_count';
  static const int dailyLimit = 15;

  /// 오늘 기준 15회 미만이면 카운트를 1 올리고 `true`, 이미 15회 이상이면 `false`.
  Future<bool> checkAndIncrementUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayYmd();
    final saved = prefs.getString(_prefsKeyDate) ?? '';
    var count = prefs.getInt(_prefsKeyCount) ?? 0;
    if (saved != today) {
      count = 0;
      await prefs.setString(_prefsKeyDate, today);
    }
    if (count >= dailyLimit) return false;
    await prefs.setInt(_prefsKeyCount, count + 1);
    return true;
  }

  String _todayYmd() {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
// GEMINI_HYBRID_PARSE_END

import 'package:flutter/foundation.dart';
import '../services/db_helper.dart';
import '../utils/work_date_utils.dart';

class TodayStatsProvider extends ChangeNotifier {
  static final TodayStatsProvider instance = TodayStatsProvider._internal();

  factory TodayStatsProvider() => instance;

  TodayStatsProvider._internal();

  int totalLogs = 0;
  int todayLogs = 0;
  int todayGross = 0;
  int todayNet = 0;
  int todayExpenses = 0;
  List<Map<String, dynamic>> recentLogs = [];
  String currentWorkDateYmd = '';

  Future<void> refresh() async {
    try {
      currentWorkDateYmd = WorkDateUtils.effectiveWorkDateYmd();
      final summary = await DriveLogDatabase.instance.getTodayStatsByWorkDate(currentWorkDateYmd);
      recentLogs = await DriveLogDatabase.instance.getRecentLogs(limit: 5);
      
      totalLogs = await DriveLogDatabase.instance.getTotalLogCount();
      todayLogs = summary['count'] as int? ?? 0;
      todayGross = summary['gross'] as int? ?? 0;
      todayNet = summary['net'] as int? ?? 0;
      todayExpenses = summary['expenses'] as int? ?? 0;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('TodayStatsProvider refresh failed: $e');
      }
    }
  }
}

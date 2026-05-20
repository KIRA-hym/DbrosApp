import 'package:intl/intl.dart';

import 'db_helper.dart';

int _statsRowRevenue(Map<String, dynamic> log) {
  final gross = _intField(log, 'gross_fare');
  final tip = _intField(log, 'waypoint_tip');
  return gross + tip;
}

int _statsRowNet(Map<String, dynamic> log) {
  final gross = _intField(log, 'gross_fare');
  final tip = _intField(log, 'waypoint_tip');
  final fee = _intField(log, 'fee');
  final transport = _intField(log, 'transport_cost');
  return gross - fee - transport + tip;
}

int _intField(Map<String, dynamic> log, String key) {
  final v = log[key];
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

/// 홈·통계 일간 차트용 (근무일 기준).
class DailyChartData {
  DailyChartData._();

  static const List<String> _fixedPrograms = <String>[
    '카카오(일반)',
    '카카오(프콜)',
    '로지',
    '콜마너',
    '티맵',
    '핸들포유',
    '기타',
  ];

  static Future<List<Map<String, dynamic>>> programStatsForWorkDate(String workDateYmd) async {
    final logs = await DriveLogDatabase.instance.getLogsForWorkDateStrict(workDateYmd);
    final programRevenue = {for (final p in _fixedPrograms) p: 0};
    final programCount = {for (final p in _fixedPrograms) p: 0};

    for (final log in logs) {
      var program = log['program'] as String? ?? '기타';
      if (program.contains('카카오')) {
        program = program.contains('프콜') ? '카카오(프콜)' : '카카오(일반)';
      }
      if (!_fixedPrograms.contains(program)) program = '기타';
      programRevenue[program] = (programRevenue[program] ?? 0) + _statsRowRevenue(log);
      programCount[program] = (programCount[program] ?? 0) + 1;
    }

    return _fixedPrograms
        .map((program) => {
              'program': program,
              'revenue': programRevenue[program] ?? 0,
              'count': programCount[program] ?? 0,
            })
        .where((e) => (e['revenue'] as int) > 0 || (e['count'] as int) > 0)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> hourlyNetForWorkDate(String workDateYmd) async {
    final logs = await DriveLogDatabase.instance.getLogsForWorkDateStrict(workDateYmd);
    final byHour = <int, int>{};
    final countByHour = <int, int>{};
    for (final log in logs) {
      final time = log['drive_time'] as String? ?? '';
      final hour = (int.tryParse(time.split(':').first) ?? 0).clamp(0, 23);
      byHour[hour] = (byHour[hour] ?? 0) + _statsRowNet(log);
      countByHour[hour] = (countByHour[hour] ?? 0) + 1;
    }
    final sorted = byHour.keys.toList()..sort();
    return sorted
        .map((h) => {
              'hour': '$h시',
              'revenue': byHour[h] ?? 0,
              'count': countByHour[h] ?? 0,
            })
        .toList();
  }

  static String todayWorkDateYmd() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }
}

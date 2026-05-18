import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/db_helper.dart';
import '../config/feature_flags.dart';

int _intField(Map<String, dynamic> log, String key) {
  final v = log[key];
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

int _statsRowRevenue(Map<String, dynamic> log) =>
    _intField(log, 'gross_fare') + _intField(log, 'waypoint_tip');

/// 목록과 동일: 순수익 = 요금 + 경유팁 − 수수료 − 교통비 (행 단위 하한 0).
int _statsRowNet(Map<String, dynamic> log) {
  final gross = _intField(log, 'gross_fare');
  final tip = _intField(log, 'waypoint_tip');
  final fee = _intField(log, 'fee');
  final transport = _intField(log, 'transport_cost');
  return (gross + tip - fee - transport).clamp(0, 999999999);
}

void _addDistinctWorkDate(Set<String> out, Map<String, dynamic> log) {
  final w = log['work_date']?.toString().trim();
  if (w != null && w.isNotEmpty) out.add(w);
}

int _distinctWorkDateCount(List<Map<String, dynamic>> logs) {
  final s = <String>{};
  for (final log in logs) {
    _addDistinctWorkDate(s, log);
  }
  return s.length;
}

/// 달력 한 장 기준 주차: 1일~첫 월요일 직전까지 = 1주차, 이후는 월요일마다 한 주씩 증가.
/// 월이 월요일로 시작하면 `((일-1)~/7)+1`과 같다.
int _koreanWeekOfMonth(DateTime d) {
  final dayOnly = DateTime(d.year, d.month, d.day);
  final first = DateTime(d.year, d.month, 1);
  var firstMonday = first;
  while (firstMonday.weekday != DateTime.monday) {
    firstMonday = firstMonday.add(const Duration(days: 1));
  }
  if (firstMonday.day == 1) {
    return ((dayOnly.day - 1) ~/ 7) + 1;
  }
  if (dayOnly.isBefore(firstMonday)) return 1;
  return (dayOnly.difference(firstMonday).inDays ~/ 7) + 2;
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String _selectedPeriod = "일간";
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _chartData = [];
  List<Map<String, dynamic>> _secondChartData = [];
  bool _isLoading = true;
  bool _isBarChart = true;
  DateTime _selectedDate = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    
    try {
      Map<String, dynamic> stats = {};
      List<Map<String, dynamic>> chartData = [];
      List<Map<String, dynamic>> secondChartData = [];

      if (_selectedPeriod == "일간") {
        stats = await _getDailyStats(_selectedDate);
        chartData = await _getProgramStats(_selectedDate, 'daily');
        secondChartData = await _getHourlyStats(_selectedDate);
      } else if (_selectedPeriod == "주간") {
        stats = await _getWeeklyStats(_selectedDate);
        chartData = await _getProgramStats(_selectedDate, 'weekly');
        secondChartData = await _getWeeklyDayStats(_selectedDate);
      } else if (_selectedPeriod == "월간") {
        stats = await _getMonthlyStats(_selectedDate);
        chartData = await _getProgramStats(_selectedDate, 'monthly');
        secondChartData = await _getMonthlyDayStats(_selectedDate);
      } else if (_selectedPeriod == "연간") {
        stats = await _getYearlyStats(_selectedDate);
        chartData = await _getProgramStats(_selectedDate, 'yearly');
        secondChartData = await _getYearlyMonthStats(_selectedDate);
      }

      setState(() {
        _stats = stats;
        _chartData = chartData;
        _secondChartData = secondChartData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _changeDate(int days) {
    final DateTime newDate = _selectedDate.add(Duration(days: days));
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime newDateOnly = DateTime(newDate.year, newDate.month, newDate.day);

    if (newDateOnly.isAfter(today)) return;
    
    setState(() => _selectedDate = newDate);
    _loadStats();
  }

  void _changeWeek(int weeks) {
    final DateTime newDate = _selectedDate.add(Duration(days: weeks * 7));
    final DateTime newDateOnly = DateTime(newDate.year, newDate.month, newDate.day);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (newDateOnly.isAfter(today)) return;
    setState(() => _selectedDate = newDate);
    _loadStats();
  }

  void _changeMonth(int months) {
    final DateTime newDate = DateTime(_selectedDate.year, _selectedDate.month + months, 1);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (newDate.isAfter(today)) return;
    setState(() => _selectedDate = newDate);
    _loadStats();
  }

  void _changeYear(int years) {
    final DateTime newDate = DateTime(_selectedDate.year + years, 1, 1);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (newDate.isAfter(today)) return;
    setState(() => _selectedDate = newDate);
    _loadStats();
  }

  double _uiFontScale(BuildContext context) => 1.0;

  String _getDailyDisplayText() => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String _getWeeklyDisplayText() {
    final int weekNumber = _koreanWeekOfMonth(_selectedDate);
    return '${DateFormat('M월').format(_selectedDate)} $weekNumber주차';
  }
  String _getMonthlyDisplayText() => DateFormat('yyyy-MM').format(_selectedDate);
  String _getYearlyDisplayText() => DateFormat('yyyy').format(_selectedDate);

  Widget _buildDateSelector() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final iconSize = isTablet ? 24.0 : 20.0;
    final padding = isTablet ? 12.0 : 8.0;
    final buttonSize = isTablet ? 40.0 : 32.0;

    String displayText = '';
    VoidCallback? onPrevious;
    VoidCallback? onNext;

    if (_selectedPeriod == "일간") {
      displayText = _getDailyDisplayText();
      onPrevious = () => _changeDate(-1);
      onNext = () => _changeDate(1);
    } else if (_selectedPeriod == "주간") {
      displayText = _getWeeklyDisplayText();
      onPrevious = () => _changeWeek(-1);
      onNext = () => _changeWeek(1);
    } else if (_selectedPeriod == "월간") {
      displayText = _getMonthlyDisplayText();
      onPrevious = () => _changeMonth(-1);
      onNext = () => _changeMonth(1);
    } else if (_selectedPeriod == "연간") {
      displayText = _getYearlyDisplayText();
      onPrevious = () => _changeYear(-1);
      onNext = () => _changeYear(1);
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime selDateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final bool canGoNext = _selectedPeriod == "일간" 
        ? selDateOnly.isBefore(today)
        : _selectedPeriod == "주간"
            ? selDateOnly.add(const Duration(days: 7)).isBefore(today) || selDateOnly.add(const Duration(days: 7)).isAtSameMomentAs(today)
            : _selectedPeriod == "월간"
                ? DateTime(selDateOnly.year, selDateOnly.month + 1, 1).isBefore(today) || DateTime(selDateOnly.year, selDateOnly.month + 1, 1).isAtSameMomentAs(today)
                : DateTime(selDateOnly.year + 1, 1, 1).isBefore(today) || DateTime(selDateOnly.year + 1, 1, 1).isAtSameMomentAs(today);

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: Icon(Icons.chevron_left, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
          SizedBox(width: padding),
          Container(
            padding: EdgeInsets.symmetric(horizontal: padding * 1.5, vertical: padding),
            child: Text(displayText, style: TextStyle(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold, fontSize: (isTablet ? 16.0 : 14.0) * _uiFontScale(context))),
          ),
          SizedBox(width: padding),
          IconButton(
            onPressed: canGoNext ? onNext : null,
            icon: Icon(Icons.chevron_right, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _getDailyStats(DateTime date) async {
    final String dateStr = DateFormat('yyyy-MM-dd').format(date);
    final stats = await DriveLogDatabase.instance.getTodayStatsByWorkDate(dateStr);
    return {
      'totalRevenue': stats['gross'] ?? 0,
      'totalNet': stats['net'] ?? 0,
      'totalExpenses': stats['expenses'] ?? 0,
      'workDays': 1,
      'totalCount': stats['count'] ?? 0,
    };
  }

  Future<Map<String, dynamic>> _getWeeklyStats(DateTime date) async {
    final DateTime weekStart = date.subtract(Duration(days: date.weekday - 1));
    final String startStr = DateFormat('yyyy-MM-dd').format(weekStart);
    final String endStr = DateFormat('yyyy-MM-dd').format(weekStart.add(const Duration(days: 6)));
    final logs = await DriveLogDatabase.instance.getLogsByWorkDateRangeStrict(startStr, endStr);
    int totalRevenue = 0, totalNet = 0, totalExpenses = 0;
    for (final log in logs) {
      totalRevenue += _statsRowRevenue(log);
      totalNet += _statsRowNet(log);
      totalExpenses += (log['fee'] as int? ?? 0) + (log['transport_cost'] as int? ?? 0);
    }
    return {
      'totalRevenue': totalRevenue,
      'totalNet': totalNet,
      'totalExpenses': totalExpenses,
      'workDays': _distinctWorkDateCount(logs),
      'totalCount': logs.length,
    };
  }

  Future<Map<String, dynamic>> _getMonthlyStats(DateTime date) async {
    final String yearMonth = DateFormat('yyyy-MM').format(date);
    final logs = await DriveLogDatabase.instance.getLogsByWorkMonthStrict(yearMonth);
    int totalRevenue = 0, totalNet = 0, totalExpenses = 0;
    for (var log in logs) {
      totalRevenue += _statsRowRevenue(log);
      totalNet += _statsRowNet(log);
      totalExpenses += (log['fee'] as int? ?? 0) + (log['transport_cost'] as int? ?? 0);
    }
    return {
      'totalRevenue': totalRevenue,
      'totalNet': totalNet,
      'totalExpenses': totalExpenses,
      'workDays': _distinctWorkDateCount(logs),
      'totalCount': logs.length,
    };
  }

  Future<Map<String, dynamic>> _getYearlyStats(DateTime date) async {
    int totalRevenue = 0, totalNet = 0, totalExpenses = 0, totalCount = 0;
    final Set<String> distinctWorkDates = {};
    for (int month = 1; month <= 12; month++) {
      final String yearMonth = DateFormat('yyyy-MM').format(DateTime(date.year, month));
      final logs = await DriveLogDatabase.instance.getLogsByWorkMonthStrict(yearMonth);
      for (var log in logs) {
        totalRevenue += _statsRowRevenue(log);
        totalNet += _statsRowNet(log);
        totalExpenses += (log['fee'] as int? ?? 0) + (log['transport_cost'] as int? ?? 0);
        totalCount++;
        _addDistinctWorkDate(distinctWorkDates, log);
      }
    }
    return {
      'totalRevenue': totalRevenue,
      'totalNet': totalNet,
      'totalExpenses': totalExpenses,
      'workDays': distinctWorkDates.length,
      'totalCount': totalCount,
    };
  }

  Future<List<Map<String, dynamic>>> _getProgramStats(DateTime date, String period) async {
    final List<String> fixedPrograms = [
      "카카오",
      "로지",
      "콜마너",
      "티맵",
      "핸들포유",
      "기타",
    ];
    Map<String, int> programRevenue = { for (var p in fixedPrograms) p: 0 };
    Map<String, int> programCount = { for (var p in fixedPrograms) p: 0 };

    void processLogs(List<Map<String, dynamic>> logs) {
      for (var log in logs) {
        String program = log['program'] as String? ?? '기타';
        if (program.contains('카카오')) {
          program = '카카오';
        }
        if (!fixedPrograms.contains(program)) program = '기타';
        programRevenue[program] = (programRevenue[program]!) + _statsRowRevenue(log);
        programCount[program] = (programCount[program]!) + 1;
      }
    }

    if (period == 'daily') {
      final String dateStr = DateFormat('yyyy-MM-dd').format(date);
      processLogs(await DriveLogDatabase.instance.getLogsForWorkDateStrict(dateStr));
    } else if (period == 'weekly') {
      final DateTime weekStart = date.subtract(Duration(days: date.weekday - 1));
      final String startStr = DateFormat('yyyy-MM-dd').format(weekStart);
      final String endStr = DateFormat('yyyy-MM-dd').format(weekStart.add(const Duration(days: 6)));
      processLogs(await DriveLogDatabase.instance.getLogsByWorkDateRangeStrict(startStr, endStr));
    } else if (period == 'monthly') {
      processLogs(await DriveLogDatabase.instance.getLogsByWorkMonthStrict(DateFormat('yyyy-MM').format(date)));
    } else if (period == 'yearly') {
      for (int month = 1; month <= 12; month++) {
        processLogs(await DriveLogDatabase.instance.getLogsByWorkMonthStrict(DateFormat('yyyy-MM').format(DateTime(date.year, month))));
      }
    }

    return fixedPrograms.map((program) => {
      'program': program,
      'revenue': programRevenue[program],
      'count': programCount[program],
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getHourlyStats(DateTime date) async {
    final String dateStr = DateFormat('yyyy-MM-dd').format(date);
    final logs = await DriveLogDatabase.instance.getLogsForWorkDateStrict(dateStr);
    final Map<int, int> byHour = {};
    for (final log in logs) {
      final String time = log['drive_time'] as String? ?? '';
      final int hour = int.tryParse(time.split(':')[0]) ?? 0;
      final h = hour.clamp(0, 23);
      byHour[h] = (byHour[h] ?? 0) + _statsRowNet(log);
    }
    final sortedHours = byHour.keys.toList()..sort();
    return sortedHours.map((h) => {'hour': '$h시', 'revenue': byHour[h] ?? 0}).toList();
  }

  Future<List<Map<String, dynamic>>> _getWeeklyDayStats(DateTime date) async {
    const kDow = ['월', '화', '수', '목', '금', '토', '일'];
    final DateTime weekStart = date.subtract(Duration(days: date.weekday - 1));
    final String startStr = DateFormat('yyyy-MM-dd').format(weekStart);
    final String endStr = DateFormat('yyyy-MM-dd').format(weekStart.add(const Duration(days: 6)));
    final logs = await DriveLogDatabase.instance.getLogsByWorkDateRangeStrict(startStr, endStr);

    final Map<String, int> revenueByYmd = {
      for (int i = 0; i < 7; i++)
        DateFormat('yyyy-MM-dd').format(weekStart.add(Duration(days: i))): 0,
    };
    for (final log in logs) {
      final wd = log['work_date']?.toString().trim() ?? '';
      if (wd.isEmpty || !revenueByYmd.containsKey(wd)) continue;
      revenueByYmd[wd] = (revenueByYmd[wd] ?? 0) + _statsRowNet(log);
    }

    final List<Map<String, dynamic>> out = [];
    for (int i = 0; i < 7; i++) {
      final slotDate = weekStart.add(Duration(days: i));
      final ymd = DateFormat('yyyy-MM-dd').format(slotDate);
      final dow = kDow[slotDate.weekday - 1];
      final label = '${slotDate.month}/${slotDate.day}($dow)';
      out.add({'day': label, 'revenue': revenueByYmd[ymd] ?? 0});
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _getMonthlyDayStats(DateTime date) async {
    final String yearMonth = DateFormat('yyyy-MM').format(date);
    final logs = await DriveLogDatabase.instance.getLogsByWorkMonthStrict(yearMonth);
    final int lastDay = DateTime(date.year, date.month + 1, 0).day;
    Map<String, int> dailyRevenue = { for (int d = 1; d <= lastDay; d++) '$d일': 0 };
    for (var log in logs) {
      final wd = log['work_date']?.toString().trim() ?? '';
      if (wd.isEmpty) continue;
      DateTime parsed;
      try {
        parsed = DateFormat('yyyy-MM-dd').parseStrict(wd);
      } catch (_) {
        continue;
      }
      if (parsed.year != date.year || parsed.month != date.month) continue;
      final day = parsed.day;
      if (day >= 1 && day <= lastDay) {
        dailyRevenue['$day일'] = (dailyRevenue['$day일'] ?? 0) + _statsRowNet(log);
      }
    }
    return dailyRevenue.entries.map((entry) => { 'day': entry.key, 'revenue': entry.value }).toList();
  }

  Future<List<Map<String, dynamic>>> _getYearlyMonthStats(DateTime date) async {
    Map<String, int> monthlyRevenue = {};
    for (int m = 1; m <= 12; m++) {
      final logs = await DriveLogDatabase.instance.getLogsByWorkMonthStrict(DateFormat('yyyy-MM').format(DateTime(date.year, m)));
      monthlyRevenue['$m월'] = logs.fold(0, (sum, log) => sum + _statsRowNet(log));
    }
    return monthlyRevenue.entries.map((entry) => { 'month': entry.key, 'revenue': entry.value }).toList();
  }

  Future<List<Map<String, dynamic>>> _getLogsForSelectedPeriod() async {
    if (_selectedPeriod == "일간") {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      return DriveLogDatabase.instance.getLogsForWorkDateStrict(dateStr);
    }
    if (_selectedPeriod == "주간") {
      final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final startStr = DateFormat('yyyy-MM-dd').format(weekStart);
      final endStr = DateFormat('yyyy-MM-dd').format(weekStart.add(const Duration(days: 6)));
      return DriveLogDatabase.instance.getLogsByWorkDateRangeStrict(startStr, endStr);
    }
    if (_selectedPeriod == "월간") {
      final yearMonth = DateFormat('yyyy-MM').format(_selectedDate);
      final logs = await DriveLogDatabase.instance.getLogsByWorkMonthStrict(yearMonth);
      logs.sort((a, b) {
        final aw = (a['work_date'] ?? '').toString();
        final bw = (b['work_date'] ?? '').toString();
        final cmpDate = aw.compareTo(bw);
        if (cmpDate != 0) return cmpDate;
        return (a['drive_time'] ?? '').toString().compareTo((b['drive_time'] ?? '').toString());
      });
      return logs;
    }
    final out = <Map<String, dynamic>>[];
    for (int month = 1; month <= 12; month++) {
      final logs = await DriveLogDatabase.instance
          .getLogsByWorkMonthStrict(DateFormat('yyyy-MM').format(DateTime(_selectedDate.year, month)));
      out.addAll(logs);
    }
    out.sort((a, b) {
      final aw = (a['work_date'] ?? '').toString();
      final bw = (b['work_date'] ?? '').toString();
      final cmpDate = aw.compareTo(bw);
      if (cmpDate != 0) return cmpDate;
      return (a['drive_time'] ?? '').toString().compareTo((b['drive_time'] ?? '').toString());
    });
    return out;
  }

  List<_TripSegment> _buildTripSegments(List<Map<String, dynamic>> logs) {
    final trips = <_TripSegment>[];
    for (final log in logs) {
      final startLat = (log['start_lat'] as num?)?.toDouble();
      final startLng = (log['start_lng'] as num?)?.toDouble();
      final endLat = (log['end_lat'] as num?)?.toDouble();
      final endLng = (log['end_lng'] as num?)?.toDouble();
      final time = (log['drive_time'] ?? '').toString();
      final program = (log['program'] ?? '').toString();
      if (startLat != null && startLng != null && endLat != null && endLng != null) {
        trips.add(
          _TripSegment(
            start: LatLng(startLat, startLng),
            end: LatLng(endLat, endLng),
            snippet: '$time · $program',
          ),
        );
      }
    }
    return trips;
  }

  Future<void> _openRouteMap() async {
    if (!kMapFeaturesEnabled) return;
    final logs = await _getLogsForSelectedPeriod();
    if (!mounted) return;
    final segments = _buildTripSegments(logs);
    if (segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택된 기간에 좌표 데이터가 없습니다.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _StatsRouteMapPage(
          periodLabel: _selectedPeriod,
          dateLabel: _selectedPeriod == '일간'
              ? _getDailyDisplayText()
              : _selectedPeriod == '주간'
                  ? _getWeeklyDisplayText()
                  : _selectedPeriod == '월간'
                      ? _getMonthlyDisplayText()
                      : _getYearlyDisplayText(),
          segments: segments,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 24.0 : math.min(16.0, screenWidth * 0.04);
    final fontScale = _uiFontScale(context);
    final appBarFontSize = (isTablet ? 20.0 : 18.0) * fontScale;
    final buttonFontSize = (isTablet ? 14.0 : 12.0) * fontScale;
    final sectionTitleFontSize = (isTablet ? 18.0 : 16.0) * fontScale;
    final statCardTitleFontSize = (isTablet ? 16.0 : 14.0) * fontScale;
    final statCardValueFontSize = (isTablet ? 24.0 : 22.0) * fontScale;
    final chartTitleFontSize = (isTablet ? 14.0 : 12.0) * fontScale;

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text(
          "운행 일지 통계",
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: const Color(0xFFFFC700),
            fontSize: appBarFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
        : LayoutBuilder(
              builder: (context, constraints) {
                final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : screenHeight * 0.75;
                final maxW = constraints.maxWidth;
                final compact = maxH < 520 || maxW < 340;
                final tight = maxH < 580;
                final gapSm = compact ? 8.0 : (isTablet ? 24.0 : 16.0);
                final gapMd = compact ? 10.0 : (isTablet ? 20.0 : 12.0);
                final gapBetweenCharts = compact ? 8.0 : 12.0;
                final gridAspect = tight
                    ? (maxW < 360 ? 1.35 : 1.45)
                    : (compact ? 1.55 : 1.8);

                return Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Wrap(
                        spacing: compact ? 6 : 10,
                        runSpacing: compact ? 6 : 10,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: ["일간", "주간", "월간", "연간"].map((t) => ElevatedButton(
                          onPressed: () { setState(() => _selectedPeriod = t); _loadStats(); },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t == _selectedPeriod ? const Color(0xFFFFC700) : const Color(0xFF1F222A),
                            foregroundColor: t == _selectedPeriod ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 12 : (isTablet ? 20 : 16),
                              vertical: compact ? 6 : 8,
                            ),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontFamily: 'GmarketSans',
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? buttonFontSize * 0.92 : buttonFontSize,
                            ),
                          ),
                        )).toList(),
                        ),
                      ),
                      SizedBox(height: gapSm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              "전체 통계",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'GmarketSans',
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: sectionTitleFontSize,
                              ),
                            ),
                          ),
                          if (kMapFeaturesEnabled) ...[
                            IconButton(
                              onPressed: _openRouteMap,
                              icon: const Icon(Icons.map, color: Color(0xFFFFC700)),
                              tooltip: '기간 경로 지도',
                            ),
                            const SizedBox(width: 8),
                          ],
                          SizedBox(width: compact ? 6 : 10),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _buildDateSelector(),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: gapMd),
                      Expanded(
                        flex: 2,
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: compact ? 8 : 12,
                          mainAxisSpacing: compact ? 8 : 12,
                          childAspectRatio: gridAspect,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _statCard("총 매출", NumberFormat('#,###').format(_stats['totalRevenue'] ?? 0), Colors.green, statCardTitleFontSize, statCardValueFontSize),
                            _statCard("총 순수익", NumberFormat('#,###').format(_stats['totalNet'] ?? 0), const Color(0xFFFFC700), statCardTitleFontSize, statCardValueFontSize),
                            _statCard("총 지출", NumberFormat('#,###').format(_stats['totalExpenses'] ?? 0), const Color(0xFFFF5252), statCardTitleFontSize, statCardValueFontSize),
                            if (_selectedPeriod != "일간")
                              _statCard(
                                "근무일수 / 운행건수",
                                '${_stats['workDays'] ?? 0} / ${_stats['totalCount'] ?? 0}',
                                Colors.white,
                                statCardTitleFontSize,
                                statCardValueFontSize,
                              ),
                            if (_selectedPeriod == "일간") _statCard("운행 건수", '${_stats['totalCount'] ?? 0}', Colors.white, statCardTitleFontSize, statCardValueFontSize),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      Text(
                        "수익 분석",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: sectionTitleFontSize),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            Expanded(child: _buildProgramChart(chartTitleFontSize)),
                            SizedBox(height: gapBetweenCharts),
                            Expanded(child: _buildSecondChart(chartTitleFontSize)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _statCard(String title, String value, Color color, double titleFontSize, double valueFontSize) {
    return Container(
      padding: EdgeInsets.all(math.min(12, titleFontSize)),
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: const Color(0xFF6E717C), fontWeight: FontWeight.bold, fontSize: titleFontSize),
          ),
          SizedBox(height: math.min(8, titleFontSize * 0.5)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: valueFontSize),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramChart(double titleFontSize) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "프로그램별 매출",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: titleFontSize),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _chartData.isEmpty 
                ? const Center(child: Text("데이터가 없습니다", style: TextStyle(color: Color(0xFF6E717C))))
                : _buildBarChart(_chartData, 'program', 'revenue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondChart(double titleFontSize) {
    String title = _selectedPeriod == "일간"
        ? "시간대별 순수익"
        : (_selectedPeriod == "주간"
            ? "요일별 순수익 (근무일 기준)"
            : (_selectedPeriod == "월간" ? "일자별 순수익 (근무일 기준)" : "월별 순수익 (근무일 기준)"));
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: titleFontSize),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _secondChartData.isEmpty 
                ? const Center(child: Text("데이터가 없습니다", style: TextStyle(color: Color(0xFF6E717C))))
                : _buildBarChart(_secondChartData, _getSecondChartKey(), 'revenue'),
            ),
          ],
        ),
      ),
    );
  }

  String _getSecondChartKey() {
    if (_selectedPeriod == "일간") return 'hour';
    if (_selectedPeriod == "주간" || _selectedPeriod == "월간") return 'day';
    return 'month';
  }

  Widget _buildBarChart(List<Map<String, dynamic>> data, String labelKey, String valueKey) {
    if (data.isEmpty) return const SizedBox();
    final totalSum = data.fold(0, (sum, item) => sum + ((item[valueKey] as int?) ?? 0));
    final displayMaxValue = totalSum > 0 ? totalSum.toDouble() : 1.0;
    return GestureDetector(
      onTap: () => setState(() => _isBarChart = !_isBarChart),
      child: _isBarChart ? _buildVerticalBarChart(data, labelKey, valueKey, displayMaxValue) : _buildLineChart(data, labelKey, valueKey, displayMaxValue),
    );
  }

  Widget _buildVerticalBarChart(List<Map<String, dynamic>> data, String labelKey, String valueKey, double maxValue) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final textFontSize = (9 * _uiFontScale(context)).clamp(8.0, 13.0);
        final longestValueLen = data
            .map((item) => NumberFormat('#,###').format((item[valueKey] as int?) ?? 0).length)
            .fold<int>(1, (a, b) => a > b ? a : b);
        final valueWidthByText = (longestValueLen * textFontSize * 0.70) + 14.0;
        final minItemWidth = math.max(30.0, valueWidthByText);
        const maxItemWidth = 56.0;
        const itemSpacing = 6.0;
        final labelHeight = textFontSize + 6.0;
        final valueHeight = textFontSize + 6.0;
        const gapPlotLabels = 4.0;
        final availH = constraints.maxHeight;
        final plotHeight = availH.isFinite && availH > 0
            ? (availH - labelHeight - valueHeight - gapPlotLabels).clamp(28.0, 88.0)
            : 72.0;

        final naturalWidth = (data.length * (minItemWidth + itemSpacing)).toDouble();
        final contentWidth = naturalWidth > availableWidth ? naturalWidth : availableWidth;
        final itemWidth = (((contentWidth - (data.length * itemSpacing)) / data.length)
                .clamp(minItemWidth, math.max(maxItemWidth, minItemWidth)))
            .toDouble();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.map((item) {
                final value = (item[valueKey] as int?) ?? 0;
                final label = item[labelKey]?.toString() ?? '';
                final normalizedHeight = maxValue > 0 ? (value / maxValue) * plotHeight : 0.0;
                final barHeight = value > 0 ? normalizedHeight.clamp(2.0, plotHeight) : 0.0;

                return SizedBox(
                  width: itemWidth + itemSpacing,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: itemSpacing / 2),
                    child: Column(
                      children: [
                        SizedBox(
                          height: plotHeight,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 6,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC700),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: gapPlotLabels),
                        SizedBox(
                          height: labelHeight,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: const Color(0xFF6E717C),
                              fontSize: textFontSize,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          height: valueHeight,
                          child: Text(
                            NumberFormat('#,###').format(value),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: textFontSize,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLineChart(List<Map<String, dynamic>> data, String labelKey, String valueKey, double maxValue) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final textFontSize = (9 * _uiFontScale(context)).clamp(8.0, 13.0);
        final longestValueLen = data
            .map((item) => NumberFormat('#,###').format((item[valueKey] as int?) ?? 0).length)
            .fold<int>(1, (a, b) => a > b ? a : b);
        final valueWidthByText = (longestValueLen * textFontSize * 0.70) + 14.0;
        final minItemWidth = math.max(30.0, valueWidthByText);
        const itemSpacing = 6.0;
        final labelHeight = textFontSize + 6.0;
        final valueHeight = textFontSize + 6.0;
        const gapPlotLabels = 4.0;
        final availH = constraints.maxHeight;
        final plotHeight = availH.isFinite && availH > 0
            ? (availH - labelHeight - valueHeight - gapPlotLabels).clamp(28.0, 88.0)
            : 72.0;

        final naturalWidth = (data.length * (minItemWidth + itemSpacing)).toDouble();
        final contentWidth = naturalWidth > availableWidth ? naturalWidth : availableWidth;
        final itemWidth =
            ((contentWidth / data.length).clamp(minItemWidth, math.max(48.0, minItemWidth))).toDouble();
        final double actualWidth = itemWidth * data.length;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: actualWidth,
            child: Column(
              children: [
                SizedBox(
                  width: actualWidth,
                  height: plotHeight,
                  child: CustomPaint(
                    painter: LineChartPainter(data, valueKey, maxValue, plotHeight, itemWidth),
                  ),
                ),
                SizedBox(height: gapPlotLabels),
                Row(
                  children: data.map((item) {
                    final value = (item[valueKey] as int?) ?? 0;
                    final label = item[labelKey]?.toString() ?? '';
                    return SizedBox(
                      width: itemWidth,
                      child: Column(
                        children: [
                          SizedBox(
                            height: labelHeight,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: const Color(0xFF6E717C),
                                fontSize: textFontSize,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            height: valueHeight,
                            child: Text(
                              NumberFormat('#,###').format(value),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: textFontSize,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TripSegment {
  const _TripSegment({
    required this.start,
    required this.end,
    required this.snippet,
  });

  final LatLng start;
  final LatLng end;
  final String snippet;
}

class _StatsRouteMapPage extends StatefulWidget {
  const _StatsRouteMapPage({
    required this.periodLabel,
    required this.dateLabel,
    required this.segments,
  });

  final String periodLabel;
  final String dateLabel;
  final List<_TripSegment> segments;

  @override
  State<_StatsRouteMapPage> createState() => _StatsRouteMapPageState();
}

class _StatsRouteMapPageState extends State<_StatsRouteMapPage> {
  GoogleMapController? _controller;
  bool _roadRouteEnabled = false;
  bool _roadRouteLoading = false;
  final Map<int, List<LatLng>> _roadRouteSegments = <int, List<LatLng>>{};

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (int i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i];
      final isFirstStart = i == 0;
      final isLastEnd = i == widget.segments.length - 1;

      final startHue = _roadRouteEnabled
          ? (isFirstStart ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange)
          : BitmapDescriptor.hueGreen;
      final endHue = _roadRouteEnabled
          ? (isLastEnd ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure)
          : BitmapDescriptor.hueRed;

      markers.add(
        Marker(
          markerId: MarkerId('start_$i'),
          position: seg.start,
          infoWindow: InfoWindow(
            title: isFirstStart ? '시작' : '출발',
            snippet: seg.snippet,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(startHue),
        ),
      );
      markers.add(
        Marker(
          markerId: MarkerId('end_$i'),
          position: seg.end,
          infoWindow: InfoWindow(
            title: isLastEnd ? '종료' : '도착',
            snippet: seg.snippet,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(endHue),
        ),
      );
    }
    return markers;
  }

  List<LatLng> _orderedPathPoints() {
    final out = <LatLng>[];
    for (final seg in widget.segments) {
      out.add(seg.start);
      out.add(seg.end);
    }
    return out;
  }

  Future<List<LatLng>> _fetchRoadPath(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('OSRM route status ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = map['routes'] as List<dynamic>? ?? const [];
    if (routes.isEmpty) return [from, to];
    final geometry = routes.first['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'] as List<dynamic>? ?? const [];
    final points = <LatLng>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        final lon = (c[0] as num?)?.toDouble();
        final lat = (c[1] as num?)?.toDouble();
        if (lat != null && lon != null) points.add(LatLng(lat, lon));
      }
    }
    return points.isEmpty ? [from, to] : points;
  }

  Future<void> _toggleRoadRoute() async {
    if (_roadRouteLoading) return;
    if (_roadRouteEnabled) {
      setState(() {
        _roadRouteEnabled = false;
      });
      return;
    }
    setState(() {
      _roadRouteLoading = true;
    });
    final points = _orderedPathPoints();
    try {
      final result = <int, List<LatLng>>{};
      for (int i = 0; i < points.length - 1; i++) {
        result[i] = await _fetchRoadPath(points[i], points[i + 1]);
      }
      if (!mounted) return;
      setState(() {
        _roadRouteSegments
          ..clear()
          ..addAll(result);
        _roadRouteEnabled = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('도로 경로를 가져오지 못했습니다.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _roadRouteLoading = false;
        });
      }
    }
  }

  Set<Polyline> _buildPolylines() {
    if (_roadRouteEnabled && _roadRouteSegments.isNotEmpty) {
      final out = <Polyline>{};
      final keys = _roadRouteSegments.keys.toList()..sort();
      for (final k in keys) {
        out.add(
          Polyline(
            polylineId: PolylineId('road_$k'),
            points: _roadRouteSegments[k] ?? const [],
            color: const Color(0xFF4FC3F7),
            width: 5,
          ),
        );
      }
      return out;
    }
    final out = <Polyline>{};
    for (int i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i];
      out.add(
        Polyline(
          polylineId: PolylineId('pair_$i'),
          points: [seg.start, seg.end],
          color: const Color(0xFFFFC700),
          width: 4,
        ),
      );
    }
    return out;
  }

  LatLngBounds _boundsForPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _fitBounds() async {
    final points = _orderedPathPoints();
    if (_controller == null || points.isEmpty) return;
    if (points.length == 1) {
      await _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }
    final bounds = _boundsForPoints(points);
    await _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();
    final polylines = _buildPolylines();
    final initial = widget.segments.first.start;

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text('${widget.periodLabel} 경로 지도'),
        actions: [
          TextButton.icon(
            onPressed: _roadRouteLoading ? null : _toggleRoadRoute,
            icon: _roadRouteLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _roadRouteEnabled ? Icons.route : Icons.alt_route,
                    color: const Color(0xFFFFC700),
                  ),
            label: Text(
              _roadRouteEnabled ? '직선보기' : '도로경로보기',
              style: const TextStyle(color: Color(0xFFFFC700)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.dateLabel,
              style: const TextStyle(color: Color(0xFF9FA3AE), fontSize: 12),
            ),
          ),
        ),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: initial, zoom: 12),
        myLocationButtonEnabled: false,
        markers: markers,
        polylines: polylines,
        onMapCreated: (controller) {
          _controller = controller;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
        },
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final String valueKey;
  final double maxValue;
  final double chartHeight;
  final double itemWidth;
  
  LineChartPainter(this.data, this.valueKey, this.maxValue, this.chartHeight, this.itemWidth);
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFFFC700)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = const Color(0xFFFFC700)
      ..style = PaintingStyle.fill;
    final path = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (itemWidth * i) + (itemWidth / 2);
      final value = (data[i][valueKey] as int?) ?? 0;
      final y = maxValue > 0 ? chartHeight - (value / maxValue) * chartHeight : chartHeight;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    for (int i = 0; i < data.length; i++) {
      final x = (itemWidth * i) + (itemWidth / 2);
      final value = (data[i][valueKey] as int?) ?? 0;
      final y = maxValue > 0 ? chartHeight - (value / maxValue) * chartHeight : chartHeight;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }
  
  @override
  bool shouldRepaint(LineChartPainter oldDelegate) => true;
}
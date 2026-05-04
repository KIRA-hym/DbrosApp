import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/expense_repository.dart';
import '../widgets/simple_expense_bar_chart.dart';

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

class ExpenseStatsPage extends StatefulWidget {
  const ExpenseStatsPage({super.key});

  @override
  State<ExpenseStatsPage> createState() => _ExpenseStatsPageState();
}

class _ExpenseStatsPageState extends State<ExpenseStatsPage> {
  String _selectedPeriod = '일간';
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _byCategory = [];
  List<Map<String, dynamic>> _second = [];
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      Map<String, dynamic> stats = {};
      List<Map<String, dynamic>> cat = [];
      List<Map<String, dynamic>> sec = [];

      if (_selectedPeriod == '일간') {
        stats = await _dailyStats(_selectedDate);
        final ymd = DateFormat('yyyy-MM-dd').format(_selectedDate);
        cat = await ExpenseRepository.aggregateByCategoryForRange(ymd, ymd, includeAllDefinedCategories: true);
        cat = cat.map((e) => {'label': e['label'], 'amount': e['amount']}).toList();
        sec = [];
      } else if (_selectedPeriod == '주간') {
        stats = await _weeklyStats(_selectedDate);
        final ws = _weekStart(_selectedDate);
        final startStr = DateFormat('yyyy-MM-dd').format(ws);
        final endStr = DateFormat('yyyy-MM-dd').format(ws.add(const Duration(days: 6)));
        cat = await ExpenseRepository.aggregateByCategoryForRange(startStr, endStr, includeAllDefinedCategories: true);
        cat = cat.map((e) => {'label': e['label'], 'amount': e['amount']}).toList();
        sec = await _byWeekday(ws);
      } else if (_selectedPeriod == '월간') {
        stats = await _monthlyStats(_selectedDate);
        final ym = DateFormat('yyyy-MM').format(_selectedDate);
        final startStr = '$ym-01';
        final last = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
        final endStr = '$ym-${last.toString().padLeft(2, '0')}';
        cat = await ExpenseRepository.aggregateByCategoryForRange(startStr, endStr, includeAllDefinedCategories: true);
        cat = cat.map((e) => {'label': e['label'], 'amount': e['amount']}).toList();
        sec = await _byDayOfMonth(_selectedDate);
      } else if (_selectedPeriod == '연간') {
        stats = await _yearlyStats(_selectedDate);
        final y = _selectedDate.year;
        final startStr = '$y-01-01';
        final endStr = '$y-12-31';
        cat = await ExpenseRepository.aggregateByCategoryForRange(startStr, endStr, includeAllDefinedCategories: true);
        cat = cat.map((e) => {'label': e['label'], 'amount': e['amount']}).toList();
        sec = await _byMonthOfYear(y);
      }

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _byCategory = cat;
        _second = sec;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _weekStart(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  Future<Map<String, dynamic>> _dailyStats(DateTime date) async {
    final ymd = DateFormat('yyyy-MM-dd').format(date);
    final rows = await ExpenseRepository.getEntriesForExpenseDate(ymd);
    var sum = 0;
    for (final e in rows) {
      sum += (e['amount'] as num?)?.toInt() ?? 0;
    }
    return {'totalExpense': sum, 'totalCount': rows.length};
  }

  Future<Map<String, dynamic>> _weeklyStats(DateTime date) async {
    final ws = _weekStart(date);
    final startStr = DateFormat('yyyy-MM-dd').format(ws);
    final endStr = DateFormat('yyyy-MM-dd').format(ws.add(const Duration(days: 6)));
    final rows = await ExpenseRepository.getEntriesByExpenseDateRange(startStr, endStr);
    var sum = 0;
    for (final e in rows) {
      sum += (e['amount'] as num?)?.toInt() ?? 0;
    }
    return {'totalExpense': sum, 'totalCount': rows.length};
  }

  Future<Map<String, dynamic>> _monthlyStats(DateTime date) async {
    final ym = DateFormat('yyyy-MM').format(date);
    final rows = await ExpenseRepository.getEntriesByExpenseMonth(ym);
    var sum = 0;
    for (final e in rows) {
      sum += (e['amount'] as num?)?.toInt() ?? 0;
    }
    return {'totalExpense': sum, 'totalCount': rows.length};
  }

  Future<Map<String, dynamic>> _yearlyStats(DateTime date) async {
    final y = date.year;
    var sum = 0;
    var cnt = 0;
    for (var m = 1; m <= 12; m++) {
      final ym = DateFormat('yyyy-MM').format(DateTime(y, m));
      final rows = await ExpenseRepository.getEntriesByExpenseMonth(ym);
      cnt += rows.length;
      for (final e in rows) {
        sum += (e['amount'] as num?)?.toInt() ?? 0;
      }
    }
    return {'totalExpense': sum, 'totalCount': cnt};
  }

  Future<List<Map<String, dynamic>>> _byWeekday(DateTime weekStart) async {
    const names = ['월', '화', '수', '목', '금', '토', '일'];
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      final ymd = DateFormat('yyyy-MM-dd').format(d);
      final sum = await ExpenseRepository.sumAmountForExpenseDate(ymd);
      out.add({'label': names[i], 'amount': sum});
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _byDayOfMonth(DateTime monthDate) async {
    final last = DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final ym = DateFormat('yyyy-MM').format(monthDate);
    final out = <Map<String, dynamic>>[];
    for (var d = 1; d <= last; d++) {
      final ymd = '$ym-${d.toString().padLeft(2, '0')}';
      final sum = await ExpenseRepository.sumAmountForExpenseDate(ymd);
      out.add({'label': '$d일', 'amount': sum});
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _byMonthOfYear(int year) async {
    final out = <Map<String, dynamic>>[];
    for (var m = 1; m <= 12; m++) {
      final ym = DateFormat('yyyy-MM').format(DateTime(year, m));
      final sum = await ExpenseRepository.sumAmountForExpenseMonth(ym);
      out.add({'label': '$m월', 'amount': sum});
    }
    return out;
  }

  void _changeDate(int days) {
    final newDate = _selectedDate.add(Duration(days: days));
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final nd = DateTime(newDate.year, newDate.month, newDate.day);
    if (nd.isAfter(todayOnly)) return;
    setState(() => _selectedDate = newDate);
    _load();
  }

  void _changeWeek(int weeks) {
    final newDate = _selectedDate.add(Duration(days: weeks * 7));
    final today = DateTime.now();
    if (newDate.isAfter(today)) return;
    setState(() => _selectedDate = newDate);
    _load();
  }

  void _changeMonth(int months) {
    final newDate = DateTime(_selectedDate.year, _selectedDate.month + months, 1);
    final today = DateTime.now();
    if (newDate.isAfter(DateTime(today.year, today.month, 1))) return;
    setState(() => _selectedDate = newDate);
    _load();
  }

  void _changeYear(int years) {
    final newDate = DateTime(_selectedDate.year + years, 1, 1);
    final today = DateTime.now();
    if (newDate.year > today.year) return;
    setState(() => _selectedDate = newDate);
    _load();
  }

  String _dateLabel() {
    if (_selectedPeriod == '일간') return DateFormat('yyyy-MM-dd').format(_selectedDate);
    if (_selectedPeriod == '주간') {
      final w = _koreanWeekOfMonth(_selectedDate);
      return '${DateFormat('M월').format(_selectedDate)} $w주차';
    }
    if (_selectedPeriod == '월간') return DateFormat('yyyy-MM').format(_selectedDate);
    return DateFormat('yyyy').format(_selectedDate);
  }

  Widget _dateSelector() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final iconSize = isTablet ? 24.0 : 20.0;
    final padding = isTablet ? 12.0 : 8.0;
    final buttonSize = isTablet ? 40.0 : 32.0;

    VoidCallback? prev;
    VoidCallback? next;
    if (_selectedPeriod == '일간') {
      prev = () => _changeDate(-1);
      next = () => _changeDate(1);
    } else if (_selectedPeriod == '주간') {
      prev = () => _changeWeek(-1);
      next = () => _changeWeek(1);
    } else if (_selectedPeriod == '월간') {
      prev = () => _changeMonth(-1);
      next = () => _changeMonth(1);
    } else {
      prev = () => _changeYear(-1);
      next = () => _changeYear(1);
    }

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    bool canNext = false;
    if (_selectedPeriod == '일간') {
      canNext = _selectedDate.isBefore(todayOnly);
    } else if (_selectedPeriod == '주간') {
      canNext = _weekStart(_selectedDate).add(const Duration(days: 7)).isBefore(todayOnly) ||
          _weekStart(_selectedDate).add(const Duration(days: 7)).isAtSameMomentAs(todayOnly);
    } else if (_selectedPeriod == '월간') {
      canNext = DateTime(_selectedDate.year, _selectedDate.month + 1, 1)
          .isBefore(DateTime(today.year, today.month + 1, 1));
    } else {
      canNext = _selectedDate.year < today.year;
    }

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: prev,
            icon: Icon(Icons.chevron_left, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
          SizedBox(width: padding),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding * 1.5, vertical: padding),
            child: Text(
              _dateLabel(),
              style: const TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          SizedBox(width: padding),
          IconButton(
            onPressed: canNext ? next : null,
            icon: Icon(Icons.chevron_right, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
        ],
      ),
    );
  }

  String _secondTitle() {
    if (_selectedPeriod == '주간') return '요일별 지출';
    if (_selectedPeriod == '월간') return '일자별 지출';
    return '월별 지출';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 24.0 : math.min(16.0, screenWidth * 0.04);

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text(
          '지출 통계',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: const Color(0xFFFFC700),
            fontSize: isTablet ? 20 : 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : screenHeight * 0.75;
                final compact = maxH < 520 || constraints.maxWidth < 340;
                final gapSm = compact ? 8.0 : (isTablet ? 24.0 : 16.0);
                final gapMd = compact ? 10.0 : (isTablet ? 20.0 : 12.0);
                final gridAspect = compact ? 1.45 : 1.75;

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
                          children: ['일간', '주간', '월간', '연간']
                              .map(
                                (t) => ElevatedButton(
                                  onPressed: () {
                                    setState(() => _selectedPeriod = t);
                                    _load();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: t == _selectedPeriod ? const Color(0xFFFFC700) : const Color(0xFF1F222A),
                                    foregroundColor: t == _selectedPeriod ? Colors.black : Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 6 : 8),
                                  ),
                                  child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      SizedBox(height: gapSm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(
                            child: Text(
                              '전체 통계',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _dateSelector(),
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
                            _statCard(
                              '총 지출',
                              NumberFormat('#,###').format(_stats['totalExpense'] ?? 0),
                              const Color(0xFFFF5252),
                            ),
                            _statCard('총 건수', '${_stats['totalCount'] ?? 0}', Colors.white),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 16),
                      const Text(
                        '수익 분석',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      Expanded(
                        flex: 3,
                        child: _selectedPeriod == '일간'
                            ? _chartBox(
                                '항목별 지출',
                                SimpleExpenseBarChart(data: _byCategory, labelKey: 'label', valueKey: 'amount'),
                              )
                            : Column(
                                children: [
                                  Expanded(
                                    child: _chartBox(
                                      '항목별 지출',
                                      SimpleExpenseBarChart(data: _byCategory, labelKey: 'label', valueKey: 'amount'),
                                    ),
                                  ),
                                  SizedBox(height: compact ? 8 : 12),
                                  Expanded(
                                    child: _chartBox(
                                      _secondTitle(),
                                      SimpleExpenseBarChart(data: _second, labelKey: 'label', valueKey: 'amount'),
                                    ),
                                  ),
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

  Widget _statCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF6E717C), fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                child: Text(
                  value,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartBox(String title, Widget chart) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Expanded(child: chart),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/expense_repository.dart';
import '../widgets/simple_expense_bar_chart.dart';
import 'expense_list_page.dart';

class ExpenseHomePage extends StatefulWidget {
  const ExpenseHomePage({super.key});

  static void requestRefresh() {
    _ExpenseHomePageState._active?.load();
  }

  @override
  State<ExpenseHomePage> createState() => _ExpenseHomePageState();
}

class _ExpenseHomePageState extends State<ExpenseHomePage> {
  static _ExpenseHomePageState? _active;
  bool _loading = true;
  int _monthTotal = 0;
  int _todayTotal = 0;
  List<Map<String, dynamic>> _byCategory = [];
  List<Map<String, dynamic>> _byDay = [];

  @override
  void initState() {
    super.initState();
    _active = this;
    load();
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    super.dispose();
  }

  Future<void> load() async {
    final now = DateTime.now();
    final ym = DateFormat('yyyy-MM').format(now);
    final todayYmd = DateFormat('yyyy-MM-dd').format(now);

    final monthTotal = await ExpenseRepository.sumAmountForExpenseMonth(ym);
    final todayTotal = await ExpenseRepository.sumAmountForExpenseDate(todayYmd);
    final byCat = await ExpenseRepository.aggregateByCategoryForMonthNonEmpty(ym);
    final chartDay = await ExpenseRepository.allDaysInMonthForChart(ym);

    final chartCat = byCat
        .map(
          (e) => <String, dynamic>{
            'label': e['label'],
            'amount': e['amount'],
          },
        )
        .toList();

    if (!mounted) return;
    setState(() {
      _monthTotal = monthTotal;
      _todayTotal = todayTotal;
      _byCategory = chartCat;
      _byDay = chartDay;
      _loading = false;
    });
  }

  void _openTodayList() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DailyExpenseListPage(
          dateStr: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          dateTitle: '지출일자: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
        ),
      ),
    ).then((_) => load());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 24.0 : 20.0;
    final titleFontSize = isTablet ? 20.0 : 18.0;
    final sectionGap = isTablet ? 12.0 : 10.0;

    final today = DateTime.now();
    final dateCompact = DateFormat('yyyy.MM.dd').format(today);
    final weekdayLong = DateFormat('EEEE', 'ko').format(today);

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121418),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20.0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: titleFontSize + 70,
                    child: Image.asset(
                      'assets/title.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 30.0, left: 4.0, right: 4.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: Text(
                          '개인지출관리',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: const Color(0xFFFFC700),
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
          : Padding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final outerPad = isTablet ? 22.0 : 16.0;
                  final innerW = constraints.maxWidth;
                  final availH = constraints.maxHeight - 2 * sectionGap;
                  final summarySectionH = availH * 34 / 100;
                  final innerCardW = innerW - 2 * outerPad;
                  final innerCardH = summarySectionH - 2 * outerPad;
                  final rowGap = (innerCardW * 0.022).clamp(8.0, 14.0);
                  final colGap = (innerCardW * 0.022).clamp(8.0, 14.0);
                  final cw = (innerCardW - colGap) / 2;
                  final ch = (innerCardH - rowGap) / 2;
                  final cell = cw < ch ? cw : ch;
                  final summaryValueFs = (cell * 0.20).clamp(26.0, 44.0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 34,
                        child: _buildSummaryCard(
                          summaryValueFontSize: summaryValueFs,
                          dateCompact: dateCompact,
                          weekdayLong: weekdayLong,
                          outerPad: outerPad,
                          onTap: _openTodayList,
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      Expanded(
                        flex: 28,
                        child: _chartSection(
                          title: '항목별 지출내역',
                          child: SimpleExpenseBarChart(data: _byCategory, labelKey: 'label', valueKey: 'amount'),
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      Expanded(
                        flex: 28,
                        child: _chartSection(
                          title: '일자별 지출내역',
                          child: SimpleExpenseBarChart(data: _byDay, labelKey: 'label', valueKey: 'amount'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildSummaryCard({
    required double summaryValueFontSize,
    required String dateCompact,
    required String weekdayLong,
    required double outerPad,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1F222A),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0xFFFFC700).withValues(alpha: 0.12),
        highlightColor: Colors.white10,
        child: Padding(
          padding: EdgeInsets.all(outerPad),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final rowGap = (w * 0.022).clamp(8.0, 14.0);
              final colGap = (w * 0.022).clamp(8.0, 14.0);
              final cw = (w - colGap) / 2;
              final ch = (h - rowGap) / 2;
              final cell = cw < ch ? cw : ch;
              final netFs = summaryValueFontSize;
              final titleTopInset = (cell * 0.06).clamp(8.0, 14.0);

              return Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16181D),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all((cell * 0.06).clamp(8.0, 14.0)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: titleTopInset),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '당월 지출',
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: netFs,
                                          height: 1.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: (cell * 0.04).clamp(6.0, 12.0)),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '${NumberFormat('#,###').format(_monthTotal)}원',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFFFF5252),
                                            fontSize: netFs,
                                            height: 1.05,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: colGap),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16181D),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all((cell * 0.06).clamp(8.0, 14.0)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: titleTopInset),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        dateCompact,
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: netFs,
                                          height: 1.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: (cell * 0.04).clamp(6.0, 12.0)),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          weekdayLong,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: netFs,
                                            height: 1.05,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: rowGap),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _mirrorCell(
                            icon: Icons.today,
                            label: '오늘 지출',
                            value: '${NumberFormat('#,###').format(_todayTotal)}원',
                            valueColor: const Color(0xFFFF5252),
                            cell: cell,
                            netFs: netFs,
                          ),
                        ),
                        SizedBox(width: colGap),
                        Expanded(
                          child: _mirrorCell(
                            icon: Icons.receipt_long,
                            label: '당월 항목 수',
                            value: '${_byCategory.length}개',
                            valueColor: const Color(0xFFFFC700),
                            cell: cell,
                            netFs: netFs,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _mirrorCell({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    required double cell,
    required double netFs,
  }) {
    final iconSz = (cell * 0.22).clamp(26.0, 48.0);
    final box = iconSz + (iconSz * 0.20).clamp(14.0, 26.0);
    final pad = EdgeInsets.all((cell * 0.06).clamp(8.0, 14.0));
    final titleTopInset = (cell * 0.06).clamp(8.0, 14.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: titleTopInset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: netFs,
                      height: 1.12,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: (cell * 0.04).clamp(6.0, 12.0)),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: box,
                    height: box,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121418),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Icon(icon, color: const Color(0xFFFFC700), size: iconSz)),
                    ),
                  ),
                  SizedBox(width: (cell * 0.035).clamp(10.0, 16.0)),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: valueColor,
                            fontSize: netFs,
                            height: 1.05,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartSection({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFFFC700),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../services/daily_chart_data.dart';
import '../utils/work_date_utils.dart';

/// 펼침 홈 왼쪽 열: 오늘(근무일) 프로그램·시간대 파이 차트.
class HomeDailyChartsPanel extends StatefulWidget {
  const HomeDailyChartsPanel({super.key});

  @override
  State<HomeDailyChartsPanel> createState() => HomeDailyChartsPanelState();
}

class HomeDailyChartsPanelState extends State<HomeDailyChartsPanel> {
  List<Map<String, dynamic>> _programData = [];
  List<Map<String, dynamic>> _hourlyData = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final ymd = DateFormat('yyyy-MM-dd').format(WorkDateUtils.effectiveWorkDateStartOfDay());
    try {
      final prog = await DailyChartData.programStatsForWorkDate(ymd);
      final hourly = await DailyChartData.hourlyNetForWorkDate(ymd);
      if (!mounted) return;
      setState(() {
        _programData = prog;
        _hourlyData = hourly;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _chartCard(
            title: '프로그램별 매출',
            data: _programData,
            labelKey: 'program',
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _chartCard(
            title: '시간대별 순수익',
            data: _hourlyData,
            labelKey: 'hour',
          ),
        ),
      ],
    );
  }

  Widget _chartCard({
    required String title,
    required List<Map<String, dynamic>> data,
    required String labelKey,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: data.isEmpty
                ? const Center(
                    child: Text('데이터가 없습니다', style: TextStyle(color: Color(0xFF6E717C), fontSize: 12)),
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _PieChartBody(data: data, valueKey: 'revenue'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _LegendList(data: data, labelKey: labelKey, valueKey: 'revenue'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PieChartBody extends StatelessWidget {
  const _PieChartBody({required this.data, required this.valueKey});

  final List<Map<String, dynamic>> data;
  final String valueKey;

  static const _colors = <Color>[
    Color(0xFFFFC700),
    Color(0xFF64B5F6),
    Color(0xFF81C784),
    Color(0xFFE57373),
    Color(0xFFBA68C8),
    Color(0xFFFFB74D),
    Color(0xFF4DD0E1),
  ];

  @override
  Widget build(BuildContext context) {
    final total = data.fold<int>(0, (s, e) => s + ((e[valueKey] as num?)?.toInt() ?? 0));
    if (total <= 0) return const SizedBox.shrink();

    var i = 0;
    final sections = data.map((item) {
      final value = (item[valueKey] as num?)?.toInt() ?? 0;
      if (value <= 0) return null;
      final color = _colors[i % _colors.length];
      i++;
      return PieChartSectionData(
        value: value.toDouble(),
        color: color,
        radius: 42,
        title: '',
      );
    }).whereType<PieChartSectionData>().toList();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 28,
        sections: sections,
      ),
    );
  }
}

class _LegendList extends StatelessWidget {
  const _LegendList({
    required this.data,
    required this.labelKey,
    required this.valueKey,
  });

  final List<Map<String, dynamic>> data;
  final String labelKey;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = data[index];
        final label = item[labelKey]?.toString() ?? '';
        final value = (item[valueKey] as num?)?.toInt() ?? 0;
        return Text(
          '$label\n${NumberFormat('#,###').format(value)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFB8BBC4), fontSize: 10, height: 1.2),
        );
      },
    );
  }
}

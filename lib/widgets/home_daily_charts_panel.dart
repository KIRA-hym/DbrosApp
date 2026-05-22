import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../services/daily_chart_data.dart';
import 'bordered_section.dart';
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
            title: '시간대별 순익',
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
    final validData = data.where((e) {
      final val = (e['revenue'] as num?)?.toInt() ?? 0;
      return val > 0;
    }).toList();

    return Container(
      decoration: BorderedSection.decoration(),
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
            child: validData.isEmpty
                ? const Center(
                    child: Text('데이터가 없습니다', style: TextStyle(color: Color(0xFF6E717C), fontSize: 12)),
                  )
                : StatsBarChartBody(
                    data: validData,
                    labelKey: labelKey,
                    valueKey: 'revenue',
                    programLabels: labelKey == 'program',
                  ),
          ),
        ],
      ),
    );
  }
}

/// 홈·통계 공용 가로형 수익 막대 리스트 위젯.
class StatsBarChartBody extends StatelessWidget {
  const StatsBarChartBody({
    super.key,
    required this.data,
    required this.labelKey,
    required this.valueKey,
    this.programLabels = false,
  });

  final List<Map<String, dynamic>> data;
  final String labelKey;
  final String valueKey;
  final bool programLabels;

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
    final maxVal = data.fold<int>(0, (prev, e) {
      final v = (e[valueKey] as num?)?.toInt() ?? 0;
      return v > prev ? v : prev;
    });

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 4, right: 8),
      itemCount: data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = data[index];
        String rawLabel = item[labelKey]?.toString() ?? '';
        if (programLabels) {
          rawLabel = rawLabel
              .replaceAll('카카오(일반)', '카(일)')
              .replaceAll('카카오(프콜)', '카(프)')
              .replaceAll('핸들포유', '핸들')
              .replaceAll('콜마너', '콜마');
        }
        final count = item['count'];
        final value = (item[valueKey] as num?)?.toInt() ?? 0;
        final color = _colors[index % _colors.length];
        final ratio = maxVal == 0 ? 0.0 : (value / maxVal).clamp(0.0, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rawLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: programLabels ? 2 : 1,
                    overflow: programLabels ? TextOverflow.visible : TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
                if (count != null)
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${count}건',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    NumberFormat('#,###').format(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      height: 6,
                      width: constraints.maxWidth * ratio,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

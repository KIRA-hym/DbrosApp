import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 통계·홈 공통: 가로 스크롤 막대 (라벨 + 값 + 막대).
class SimpleExpenseBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String labelKey;
  final String valueKey;
  final double fontScale;

  const SimpleExpenseBarChart({
    super.key,
    required this.data,
    required this.labelKey,
    required this.valueKey,
    this.fontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('데이터가 없습니다', style: TextStyle(color: Color(0xFF6E717C))));
    }
    final totalSum = data.fold<int>(0, (sum, item) => sum + ((item[valueKey] as num?)?.toInt() ?? 0));
    final maxValue = totalSum > 0 ? totalSum.toDouble() : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final textFontSize = (9 * fontScale).clamp(8.0, 13.0);
        final longestValueLen = data
            .map((item) => NumberFormat('#,###').format((item[valueKey] as num?)?.toInt() ?? 0).length)
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
            ? math.max(28.0, availH - labelHeight - valueHeight - gapPlotLabels)
            : 72.0;

        final chartColumnHeight = plotHeight + gapPlotLabels + labelHeight + valueHeight;

        final naturalWidth = (data.length * (minItemWidth + itemSpacing)).toDouble();
        final contentWidth = naturalWidth > availableWidth ? naturalWidth : availableWidth;
        final itemWidth = (((contentWidth - (data.length * itemSpacing)) / data.length)
                .clamp(minItemWidth, math.max(maxItemWidth, minItemWidth)))
            .toDouble();

        final outerH = availH.isFinite && availH > 0 ? availH : chartColumnHeight;

        return SizedBox(
          width: availableWidth,
          height: outerH,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: chartColumnHeight,
                width: contentWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: data.map((item) {
                final value = (item[valueKey] as num?)?.toInt() ?? 0;
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
                            maxLines: 2,
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
            ),
          ),
        );
      },
    );
  }
}

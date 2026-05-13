import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/app_bottom_sheet.dart';

/// 운행 통계 화면 일간 날짜 선택과 동일 스타일(좌우 화살표 + yyyy-MM-dd).
class DriveDateSelectorBar extends StatelessWidget {
  const DriveDateSelectorBar({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _minDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime _maxDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  void _prev() {
    final min = _minDate();
    final cur = _dayOnly(selectedDate);
    if (!cur.isAfter(min)) return;
    final d = cur.subtract(const Duration(days: 1));
    onDateChanged(d);
  }

  void _next() {
    final max = _maxDate();
    final sel = _dayOnly(selectedDate);
    if (!sel.isBefore(max)) return;
    onDateChanged(sel.add(const Duration(days: 1)));
  }

  Future<void> _openScrollerPicker(BuildContext context) async {
    final min = _minDate();
    final max = _maxDate();
    final dates = <DateTime>[];
    var cursor = max;
    while (!cursor.isBefore(min)) {
      dates.add(cursor);
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var selected = _dayOnly(selectedDate);
    if (selected.isBefore(min)) selected = min;
    if (selected.isAfter(max)) selected = max;

    final picked = await AppBottomSheet.show<DateTime>(
      context: context,
      backgroundColor: const Color(0xFF1F222A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final selectedIndex = dates.indexWhere((d) => d == selected);
          return SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Text('날짜 선택',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Color(0xFFFFC700)),
                        onPressed: () {
                          final prev = selected.subtract(const Duration(days: 1));
                          if (prev.isBefore(min)) return;
                          setModalState(() => selected = prev);
                        },
                      ),
                      Text(
                        DateFormat('yyyy-MM-dd').format(selected),
                        style: const TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Color(0xFFFFC700)),
                        onPressed: () {
                          final next = selected.add(const Duration(days: 1));
                          if (next.isAfter(max)) return;
                          setModalState(() => selected = next);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: dates.length,
                    itemBuilder: (ctx, i) {
                      final d = dates[i];
                      final isSelected = i == selectedIndex;
                      return ListTile(
                        title: Text(
                          DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(d),
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFFFC700) : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                          ),
                        ),
                        onTap: () => setModalState(() => selected = d),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('취소', style: TextStyle(color: Color(0xFF9FA3AE))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, selected),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC700),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('확인'),
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
    if (picked != null) onDateChanged(_dayOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final iconSize = isTablet ? 24.0 : 20.0;
    final padding = isTablet ? 12.0 : 8.0;
    final buttonSize = isTablet ? 40.0 : 32.0;
    final sel = _dayOnly(selectedDate);
    final canGoNext = sel.isBefore(_maxDate());
    final canGoPrev = sel.isAfter(_minDate());
    final displayText = DateFormat('yyyy-MM-dd').format(sel);

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: canGoPrev ? _prev : null,
            icon: Icon(Icons.chevron_left, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
          SizedBox(width: padding),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openScrollerPicker(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  displayText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFFFC700),
                    fontWeight: FontWeight.bold,
                    fontSize: isTablet ? 16.0 : 14.0,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: padding),
          IconButton(
            onPressed: canGoNext ? _next : null,
            icon: Icon(Icons.chevron_right, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
        ],
      ),
    );
  }
}

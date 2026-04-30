import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 운행 통계 화면 일간 날짜 선택과 동일 스타일(좌우 화살표 + yyyy-MM-dd).
class DriveDateSelectorBar extends StatelessWidget {
  const DriveDateSelectorBar({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  void _prev() {
    final d = DateTime(selectedDate.year, selectedDate.month, selectedDate.day).subtract(const Duration(days: 1));
    onDateChanged(d);
  }

  void _next() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    if (!sel.isBefore(today)) return;
    onDateChanged(sel.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final iconSize = isTablet ? 24.0 : 20.0;
    final padding = isTablet ? 12.0 : 8.0;
    final buttonSize = isTablet ? 40.0 : 32.0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final canGoNext = sel.isBefore(today);
    final displayText = DateFormat('yyyy-MM-dd').format(sel);

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _prev,
            icon: Icon(Icons.chevron_left, color: const Color(0xFFFFC700), size: iconSize),
            constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
          ),
          SizedBox(width: padding),
          Expanded(
            child: Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold, fontSize: isTablet ? 16.0 : 14.0),
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

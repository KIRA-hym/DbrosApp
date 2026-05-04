import 'package:flutter/material.dart';

import 'config/feature_flags.dart';
import 'expense_nav_bus.dart';
import 'main_navigation.dart';
import 'screens/expense_home_page.dart';
import 'screens/expense_list_page.dart';
import 'screens/expense_write_page.dart';
import 'screens/expense_stats_page.dart';
import 'screens/expense_settings_page.dart';
import 'services/font_size_service.dart';
import 'services/settings_service.dart';

/// 개인지출관리 전용 하단 탭 셸 (운행일지 [MainWrapper]와 동일 구조).
class ExpenseMainWrapper extends StatefulWidget {
  final int initialIndex;
  const ExpenseMainWrapper({super.key, this.initialIndex = 0});

  @override
  State<ExpenseMainWrapper> createState() => _ExpenseMainWrapperState();
}

class _ExpenseMainWrapperState extends State<ExpenseMainWrapper> {
  late int _selectedIndex;

  final List<Widget> _pages = const [
    ExpenseHomePage(),
    ExpenseListPage(),
    ExpenseWritePage(),
    ExpenseStatsPage(),
    ExpenseSettingsPage(),
  ];

  void _selectTab(int index) {
    if (index >= 0 && index < _pages.length) {
      setState(() => _selectedIndex = index);
      if (index == 0) ExpenseHomePage.requestRefresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    if (kExpenseOwnerOnly) {
      ExpenseNavBus.register(_selectTab);
    }
  }

  @override
  void dispose() {
    if (kExpenseOwnerOnly) {
      ExpenseNavBus.unregister(_selectTab);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kExpenseOwnerOnly) {
      return Scaffold(
        backgroundColor: const Color(0xFF121418),
        appBar: AppBar(
          backgroundColor: const Color(0xFF121418),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            '개인지출관리',
            style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '개인지출관리는 오너 전용 기능입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return MainTabScope(
      selectTab: _selectTab,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
            ExpenseHomePage.requestRefresh();
          } else {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          body: _pages[_selectedIndex],
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "Copyright 2026 Dbros. All rights reserved.",
                  style: TextStyle(
                    color: const Color(0xFF6E717C),
                    fontSize: FontSizeService.getScaledFontSize(10),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
                ),
                child: BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: const Color(0xFF121418),
                  selectedItemColor: const Color(0xFFFFC700),
                  unselectedItemColor: const Color(0xFF6E717C),
                  selectedFontSize: FontSizeService.getScaledFontSize(12),
                  unselectedFontSize: FontSizeService.getScaledFontSize(12),
                  selectedLabelStyle: TextStyle(
                    fontFamily: 'GmarketSans',
                    fontWeight: FontWeight.w700,
                    fontSize: FontSizeService.getScaledFontSize(12),
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontFamily: 'GmarketSans',
                    fontWeight: FontWeight.w700,
                    fontSize: FontSizeService.getScaledFontSize(12),
                  ),
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() => _selectedIndex = index);
                    if (index == 0) ExpenseHomePage.requestRefresh();
                  },
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_filled), activeIcon: Icon(Icons.home), label: '홈'),
                    BottomNavigationBarItem(icon: Icon(Icons.list_alt), activeIcon: Icon(Icons.list_alt), label: '목록'),
                    BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: '작성'),
                    BottomNavigationBarItem(icon: Icon(Icons.bar_chart), activeIcon: Icon(Icons.bar_chart), label: '통계'),
                    BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: '설정'),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: ValueListenableBuilder<double>(
            valueListenable: FontSizeService.fontNotifier,
            builder: (context, fontSize, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: SettingsService.showFloatingButtonsNotifier,
                builder: (context, showFloatingButtons, child) {
                  return showFloatingButtons
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            FloatingActionButton(
                              heroTag: 'exp_font_increase',
                              onPressed: () async {
                                final mq = MediaQuery.of(context);
                                await FontSizeService.increaseFontSizeForMediaQuery(mq);
                              },
                              backgroundColor: const Color(0xFFFFC700),
                              mini: true,
                              child: const Icon(Icons.zoom_in, color: Colors.black),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton(
                              heroTag: 'exp_font_decrease',
                              onPressed: () async {
                                await FontSizeService.decreaseFontSize();
                              },
                              backgroundColor: const Color(0xFFFFC700),
                              mini: true,
                              child: const Icon(Icons.zoom_out, color: Colors.black),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton(
                              heroTag: 'exp_font_reset',
                              onPressed: () async {
                                await FontSizeService.resetFontSize();
                              },
                              backgroundColor: const Color(0xFF1F222A),
                              mini: true,
                              child: const Icon(Icons.refresh, color: Color(0xFFFFC700)),
                            ),
                          ],
                        )
                      : const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

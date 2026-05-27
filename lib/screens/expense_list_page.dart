import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../expense_nav_bus.dart';
import '../services/expense_repository.dart';
import '../utils/responsive_layout.dart';
import '../widgets/app_glass_dialog.dart';
import '../widgets/responsive_body.dart';
import 'expense_write_page.dart';

class ExpenseListPage extends StatefulWidget {
  const ExpenseListPage({super.key});

  @override
  State<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends State<ExpenseListPage> {
  DateTime _focusedMonth = DateTime.now();
  Map<String, List<Map<String, dynamic>>> _grouped = {};
  bool _isLoading = true;
  bool _isScrolled = false;

  int _totalCount = 0;
  int _totalExpense = 0;

  /// 펼침·넓은 화면 마스터-디테일에서 선택한 지출일(yyyy-MM-dd).
  String? _masterDetailDate;
  int _detailRevision = 0;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _todayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadMonthData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + offset, 1);
      _isScrolled = false;
    });
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    setState(() => _isLoading = true);
    final String yearMonth = DateFormat('yyyy-MM').format(_focusedMonth);
    final logs = await ExpenseRepository.getEntriesByExpenseMonth(yearMonth);

    final grouped = <String, List<Map<String, dynamic>>>{};
    var expenseSum = 0;
    for (final e in logs) {
      expenseSum += (e['amount'] as num?)?.toInt() ?? 0;
      final d = e['expense_date']?.toString() ?? '';
      grouped.putIfAbsent(d, () => []).add(e);
    }

    if (!mounted) return;
    setState(() {
      _grouped = grouped;
      _totalCount = logs.length;
      _totalExpense = expenseSum;
      _isLoading = false;
      _syncMasterDetailDateInState();
      _detailRevision++;
    });
    _scrollToToday();
  }

  /// 펼침 기본 선택: 이번 달이면 **오늘** 지출일, 다른 달이면 null.
  String? _initialMasterDetailDateInFocusedMonth() {
    final now = DateTime.now();
    if (now.year == _focusedMonth.year && now.month == _focusedMonth.month) {
      return DateFormat('yyyy-MM-dd').format(now);
    }
    return null;
  }

  void _syncMasterDetailDateInState() {
    final selected = _masterDetailDate;
    if (selected != null) {
      final parsed = DateTime.tryParse(selected);
      if (parsed != null &&
          parsed.year == _focusedMonth.year &&
          parsed.month == _focusedMonth.month) {
        return;
      }
    }
    _masterDetailDate = _initialMasterDetailDateInFocusedMonth();
  }

  void _scrollToToday() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_todayKey.currentContext != null) {
        Scrollable.ensureVisible(_todayKey.currentContext!, duration: Duration.zero, alignment: 0.0);
      } else if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      if (mounted) setState(() => _isScrolled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isExpanded = ResponsiveLayout.isExpanded(context);
    if (isExpanded && _masterDetailDate == null && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final initial = _initialMasterDetailDateInFocusedMonth();
        if (initial != null) {
          setState(() => _masterDetailDate = initial);
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text(
          '지출 목록',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFC700),
              ),
        ),
        backgroundColor: const Color(0xFF1F222A),
      ),
      body: isExpanded
          ? _buildExpandedMasterDetailBody()
          : ResponsiveBody(
              child: Column(
                children: [
                  _buildMonthHeader(),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFF121418),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
                          : Opacity(
                              opacity: _isScrolled ? 1.0 : 0.0,
                              child: _buildDailyList(),
                            ),
                    ),
                  ),
                  _buildMonthlySummaryFooter(),
                ],
              ),
            ),
    );
  }

  Widget _buildExpandedMasterDetailBody() {
    final selected = _masterDetailDate;
    return Column(
      children: [
        _buildMonthHeader(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      child: ColoredBox(
                        color: const Color(0xFF121418),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Opacity(
                                opacity: _isScrolled ? 1.0 : 0.0,
                                child: _buildDailyList(
                                  masterDetailMode: true,
                                  selectedDate: selected,
                                  onSelectDate: (d) => setState(() => _masterDetailDate = d),
                                ),
                              ),
                            ),
                            _buildMasterDetailMonthlySummary(compact: true),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Colors.white10),
                    Expanded(
                      flex: 6,
                      child: selected == null
                          ? const Center(
                              child: Text(
                                '왼쪽에서 날짜를 선택하세요',
                                style: TextStyle(color: Color(0xFF6E717C)),
                              ),
                            )
                          : DailyExpenseListPage(
                              key: ValueKey('${selected}_$_detailRevision'),
                              dateStr: selected,
                              dateTitle: '지출일자: $selected',
                              embedded: true,
                              onEntriesChanged: _loadMonthData,
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMasterDetailMonthlySummary({bool compact = false}) {
    final hPad = compact ? 12.0 : 20.0;
    final vPad = compact ? 10.0 : 16.0;
    final infoFontSize = compact ? 12.0 : 13.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: const BoxDecoration(
        color: Color(0xFF1F222A),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '[ 월간 합계 ]',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$_totalCount건', style: TextStyle(color: Colors.white, fontSize: infoFontSize)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                    Expanded(
                      child: Text(
                        '₩${NumberFormat('#,###').format(_totalExpense)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: Color(0xFFFF5252),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 12.0 : 8.0;
    final iconSize = isTablet ? 28.0 : 24.0;

    return Container(
      color: const Color(0xFF1F222A),
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_left, color: Colors.white, size: iconSize),
            onPressed: () => _changeMonth(-1),
            constraints: BoxConstraints(minWidth: iconSize + 8, minHeight: iconSize + 8),
          ),
          SizedBox(width: isTablet ? 20 : 16),
          Text(
            DateFormat('yyyy년 MM월').format(_focusedMonth),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
          ),
          SizedBox(width: isTablet ? 20 : 16),
          IconButton(
            icon: Icon(Icons.arrow_right, color: Colors.white, size: iconSize),
            onPressed: () => _changeMonth(1),
            constraints: BoxConstraints(minWidth: iconSize + 8, minHeight: iconSize + 8),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyList({
    bool masterDetailMode = false,
    String? selectedDate,
    void Function(String dateStr)? onSelectDate,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final now = DateTime.now();
    final compactMaster = masterDetailMode;

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: List.generate(daysInMonth, (index) {
          final day = index + 1;
          final currentDate = DateTime(_focusedMonth.year, _focusedMonth.month, day);
          final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
          final dayOfWeek = DateFormat('E', 'ko_KR').format(currentDate);
          final isToday =
              currentDate.year == now.year && currentDate.month == now.month && currentDate.day == now.day;
          final daily = _grouped[dateStr] ?? [];

          final horizontalPadding = compactMaster ? 12.0 : (ResponsiveLayout.isTablet(context) ? 24.0 : 20.0);
          final iconSize = compactMaster ? 20.0 : (ResponsiveLayout.isTablet(context) ? 22.0 : 20.0);
          final isSelected = masterDetailMode && selectedDate == dateStr;

          if (daily.isEmpty) {
            return Container(
              key: isToday ? _todayKey : null,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2A2E38) : const Color(0xFF1F222A),
                border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                leading: Icon(Icons.label, color: isToday ? const Color(0xFFFFC700) : Colors.white70, size: iconSize),
                title: Text(
                  '${day.toString().padLeft(2, '0')} ($dayOfWeek)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isToday ? const Color(0xFFFFC700) : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                trailing: Text(
                  masterDetailMode ? '' : '<지출 입력>',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
                ),
                onTap: () {
                  if (masterDetailMode && onSelectDate != null) {
                    onSelectDate(dateStr);
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ExpenseWritePage(
                        initialExpenseDate: dateStr,
                        closeAfterSave: true,
                      ),
                    ),
                  ).then((_) => _loadMonthData());
                },
              ),
            );
          }

          var dailyExpense = 0;
          for (final e in daily) {
            dailyExpense += (e['amount'] as num?)?.toInt() ?? 0;
          }
          final logCount = daily.length;

          final verticalPadding = compactMaster ? 12.0 : (ResponsiveLayout.isTablet(context) ? 18.0 : 16.0);
          final spacing = compactMaster ? 10.0 : (ResponsiveLayout.isTablet(context) ? 14.0 : 12.0);

          return Container(
            key: isToday ? _todayKey : null,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2A2E38) : const Color(0xFF1F222A),
              border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
            ),
            child: InkWell(
              onTap: () {
                if (masterDetailMode && onSelectDate != null) {
                  onSelectDate(dateStr);
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DailyExpenseListPage(dateStr: dateStr, dateTitle: '지출일자: $dateStr'),
                  ),
                ).then((_) => _loadMonthData());
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.receipt_long, color: isToday ? const Color(0xFFFFC700) : Colors.white, size: iconSize),
                    SizedBox(width: spacing),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              '${day.toString().padLeft(2, '0')} ($dayOfWeek)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isToday ? const Color(0xFFFFC700) : Colors.white,
                                  ),
                            ),
                          ),
                          SizedBox(width: spacing),
                          Text(
                            '$logCount건',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                          ),
                          const Spacer(),
                          Flexible(
                            fit: FlexFit.loose,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '₩${NumberFormat('#,###').format(dailyExpense)}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFFFF5252),
                                      fontWeight: FontWeight.bold,
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
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMonthlySummaryFooter() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 20.0 : 16.0;
    final valueFontSize = isTablet ? 15.0 : 14.0;
    final infoFontSize = isTablet ? 14.0 : 13.0;
    final spacing = isTablet ? 8.0 : 6.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
      color: const Color(0xFF1F222A),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '[ 월간 합계 ]',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_totalCount건', style: TextStyle(color: Colors.white, fontSize: infoFontSize)),
                  SizedBox(height: spacing),
                  Row(
                    children: [
                      const Text('지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      Expanded(
                        child: Text(
                          '₩${NumberFormat('#,###').format(_totalExpense)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: const Color(0xFFFF5252),
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyExpenseListPage extends StatefulWidget {
  final String dateStr;
  final String dateTitle;
  final String? snackMessage;

  const DailyExpenseListPage({
    super.key,
    required this.dateStr,
    required this.dateTitle,
    this.snackMessage,
    this.embedded = false,
    this.onEntriesChanged,
  });

  /// 목록 마스터-디테일 오른쪽 패널용.
  final bool embedded;
  final VoidCallback? onEntriesChanged;

  @override
  State<DailyExpenseListPage> createState() => _DailyExpenseListPageState();
}

class _DailyExpenseListPageState extends State<DailyExpenseListPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _totalCount = 0;
  int _totalExpense = 0;
  bool _poppingForExpandedLayout = false;

  @override
  void initState() {
    super.initState();
    _load();
    final msg = widget.snackMessage?.trim();
    if (msg != null && msg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.embedded || _poppingForExpandedLayout) return;
    if (!ResponsiveLayout.isExpanded(context)) return;
    _poppingForExpandedLayout = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pop(context, widget.dateStr);
    });
  }

  Future<void> _openAddExpense() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ExpenseWritePage(
          initialExpenseDate: widget.dateStr,
          closeAfterSave: true,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
    widget.onEntriesChanged?.call();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await ExpenseRepository.getEntriesForExpenseDate(widget.dateStr);
    var sum = 0;
    for (final e in logs) {
      sum += (e['amount'] as num?)?.toInt() ?? 0;
    }
    if (!mounted) return;
    setState(() {
      _rows = logs;
      _totalCount = logs.length;
      _totalExpense = sum;
      _loading = false;
    });
  }

  String _writtenDateLabel(String writtenAtIso) {
    try {
      final dt = DateTime.parse(writtenAtIso);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {
      return writtenAtIso;
    }
  }

  String _writtenTimeLabel(String writtenAtIso) {
    try {
      final dt = DateTime.parse(writtenAtIso);
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  Widget _buildDailyDetailDateHeader() {
    final compact = widget.embedded;
    final padding = compact ? 6.0 : (ResponsiveLayout.isTablet(context) ? 12.0 : 8.0);
    final hPad = compact ? 8.0 : (ResponsiveLayout.isTablet(context) ? 12.0 : 8.0);
    final sideSlot = compact ? 96.0 : 0.0;
    final titleStyle = (compact ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white);
    return Container(
      color: const Color(0xFF1F222A),
      padding: EdgeInsets.symmetric(vertical: padding, horizontal: hPad),
      child: Row(
        children: [
          SizedBox(width: sideSlot),
          Expanded(
            child: Text(
              widget.dateTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          SizedBox(
            width: sideSlot,
            child: compact
                ? Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _openAddExpense,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFFFFC700)),
                      label: const Text(
                        '입력',
                        style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDailyDetailDateHeader(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
              : ColoredBox(
                  color: const Color(0xFF121418),
                  child: Column(
                    children: [
                      Expanded(child: _buildListBody()),
                      _buildFooter(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildListBody() {
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.embedded ? '이 날짜에 등록된 지출이 없습니다' : '등록된 지출이 없습니다.',
              style: const TextStyle(color: Color(0xFF6E717C), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (widget.embedded) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openAddExpense,
                icon: const Icon(Icons.add, size: 22),
                label: const Text(
                  '지출 입력',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC700),
                  foregroundColor: const Color(0xFF121418),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return _buildList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: const Color(0xFF121418),
        child: _buildDetailBody(),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final titleFontSize = isTablet ? 18.0 : 16.0;

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F222A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.dateTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleFontSize)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
                : ColoredBox(
                    color: const Color(0xFF121418),
                    child: Column(
                      children: [
                        Expanded(child: _buildListBody()),
                        _buildFooter(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF121418),
          selectedItemColor: const Color(0xFFFFC700),
          unselectedItemColor: const Color(0xFF6E717C),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          currentIndex: 1,
          onTap: (index) {
            if (index == 2) {
              ExpenseWritePage.pendingExpenseDateNotifier.value = widget.dateStr;
              ExpenseNavBus.goToTab(2);
              Navigator.of(context).popUntil((r) => r.settings.name == '/expense_main');
              return;
            }
            if (index == 1) {
              Navigator.pop(context);
              return;
            }
            ExpenseNavBus.goToTab(index);
            Navigator.of(context).popUntil((r) => r.settings.name == '/expense_main');
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
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final e = _rows[index];
        final written = e['written_at']?.toString() ?? '';
        final dateLabel = _writtenDateLabel(written);
        final timeLabel = _writtenTimeLabel(written);
        final cat = e['category_name']?.toString() ?? '';
        final amount = (e['amount'] as num?)?.toInt() ?? 0;
        final memo = (e['memo'] ?? '').toString().trim();

        final compact = widget.embedded;
        final horizontalPadding = compact ? 12.0 : (ResponsiveLayout.isTablet(context) ? 24.0 : 20.0);
        final verticalPadding = compact ? 12.0 : (ResponsiveLayout.isTablet(context) ? 18.0 : 16.0);

        return Dismissible(
          key: Key('exp_${e['id']}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: EdgeInsets.only(right: horizontalPadding),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete, color: Colors.white),
                SizedBox(height: 4),
                Text('삭제', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            return await AppGlassDialog.show<bool>(
                  context: context,
                  dialog: AppGlassDialog(
                    icon: Icons.delete_outline,
                    title: '지출 삭제',
                    content: '이 지출을 삭제하시겠습니까?\n\n$cat ${NumberFormat('#,###').format(amount)}원',
                    actions: [
                      Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx, false))),
                      Builder(builder: (ctx) => GlassDialogDestructiveButton(onPressed: () => Navigator.pop(ctx, true))),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (_) async {
            await ExpenseRepository.deleteEntry((e['id'] as num).toInt());
            await _load();
            widget.onEntriesChanged?.call();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('지출이 삭제되었습니다.'), backgroundColor: Colors.red),
              );
            }
          },
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ExpenseWritePage(existing: e, closeAfterSave: true),
                ),
              ).then((_) async {
                await _load();
                widget.onEntriesChanged?.call();
              });
            },
            child: Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5))),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '[ $dateLabel $timeLabel ]  $cat',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        '1건',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const Spacer(),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '₩${NumberFormat('#,###').format(amount)}',
                            style: const TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (memo.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      memo,
                      style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 14, height: 1.25),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    final compact = widget.embedded;
    final horizontalPadding = compact ? 12.0 : (ResponsiveLayout.isTablet(context) ? 24.0 : 20.0);
    final verticalPadding = compact ? 10.0 : (ResponsiveLayout.isTablet(context) ? 20.0 : 16.0);
    final valueFontSize = compact ? 13.0 : (ResponsiveLayout.isTablet(context) ? 15.0 : 14.0);
    final spacing = compact ? 4.0 : (ResponsiveLayout.isTablet(context) ? 8.0 : 6.0);

    return Container(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
      color: const Color(0xFF1F222A),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '[ 일일 합계 ]',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_totalCount건', style: TextStyle(color: Colors.white, fontSize: valueFontSize)),
                  SizedBox(height: spacing),
                  Row(
                    children: [
                      const Text('지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      Expanded(
                        child: Text(
                          '₩${NumberFormat('#,###').format(_totalExpense)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: const Color(0xFFFF5252),
                            fontSize: valueFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

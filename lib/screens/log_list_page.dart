import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../services/db_helper.dart';
import '../main.dart'; 
import 'write_log_page.dart';

int _intField(Map<String, dynamic> log, String key) {
  final v = log[key];
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

/// 목록·상세 공통: 수입=요금+경유팁, 지출=수수료+교통비, 순익=요금-수수료-교통비+경유팁
int _rowIncomePlusTip(Map<String, dynamic> log) =>
    _intField(log, 'gross_fare') + _intField(log, 'waypoint_tip');

int _rowExpenseFeePlusTransport(Map<String, dynamic> log) =>
    _intField(log, 'fee') + _intField(log, 'transport_cost');

int _rowNetProfit(Map<String, dynamic> log) =>
    _intField(log, 'gross_fare') -
    _intField(log, 'fee') -
    _intField(log, 'transport_cost') +
    _intField(log, 'waypoint_tip');

class LogListPage extends StatefulWidget {
  const LogListPage({super.key});
  @override
  State<LogListPage> createState() => _LogListPageState();
}

class _LogListPageState extends State<LogListPage> {
  DateTime _focusedMonth = DateTime.now();
  Map<String, List<Map<String, dynamic>>> _groupedLogs = {};
  bool _isLoading = true;
  bool _isScrolled = false;

  int _totalCount = 0;
  int _totalGross = 0;
  int _totalNet = 0;
  int _totalExpenses = 0;

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
    final logs = await DriveLogDatabase.instance.getLogsByWorkMonthStrict(yearMonth);

    Map<String, List<Map<String, dynamic>>> grouped = {};
    int count = logs.length;
    int incomeSum = 0;
    int netProfitSum = 0;
    int expenseSum = 0;

    for (var log in logs) {
      incomeSum += _rowIncomePlusTip(log);
      netProfitSum += _rowNetProfit(log);
      expenseSum += _rowExpenseFeePlusTransport(log);
      final date = log['work_date']?.toString().trim() ?? '';
      if (date.isEmpty) continue;
      grouped.putIfAbsent(date, () => []);
      grouped[date]!.add(log);
    }

    setState(() {
      _groupedLogs = grouped;
      _totalCount = count;
      _totalGross = incomeSum;
      _totalNet = netProfitSum;
      _totalExpenses = expenseSum;
      _isLoading = false;
    });

    _scrollToToday();
  }

  void _scrollToToday() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_todayKey.currentContext != null) {
        Scrollable.ensureVisible(
          _todayKey.currentContext!, 
          duration: Duration.zero,
          alignment: 0.0,
        );
      } else {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
      
      if (mounted) {
        setState(() => _isScrolled = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text("운행 일지 목록", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFFFC700))),
        backgroundColor: const Color(0xFF1F222A),
      ),
      body: Column(
        children: [
          _buildMonthHeader(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700))) 
              : Opacity(
                  opacity: _isScrolled ? 1.0 : 0.0,
                  child: _buildDailyList(),
                ),
          ),
          _buildMonthlySummaryFooter(),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)
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

  Widget _buildDailyList() {
    int daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final now = DateTime.now();
    
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: List.generate(daysInMonth, (index) {
          int day = index + 1;
          DateTime currentDate = DateTime(_focusedMonth.year, _focusedMonth.month, day);
          String dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
          String dayOfWeek = DateFormat('E', 'ko_KR').format(currentDate); 
          bool isToday = currentDate.year == now.year && currentDate.month == now.month && currentDate.day == now.day;
          List<Map<String, dynamic>> dailyLogs = _groupedLogs[dateStr] ?? [];

          if (dailyLogs.isEmpty) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isTablet = screenWidth > 600;
            final horizontalPadding = isTablet ? 24.0 : 20.0;
            final iconSize = isTablet ? 22.0 : 20.0;

            return Container(
              key: isToday ? _todayKey : null,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                leading: Icon(Icons.label, color: isToday ? const Color(0xFFFFC700) : Colors.white70, size: iconSize),
                title: Text("${day.toString().padLeft(2, '0')} ($dayOfWeek)", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isToday ? const Color(0xFFFFC700) : Colors.white70, fontWeight: FontWeight.bold)),
                trailing: Text("<일지 입력>", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => DriveLogForm(initialDate: dateStr))).then((_) => _loadMonthData());
                },
              ),
            );
          }

          int dailyIncome = 0;
          int dailyNetProfit = 0;
          int dailyExpense = 0;
          for (var log in dailyLogs) {
            dailyIncome += _rowIncomePlusTip(log);
            dailyNetProfit += _rowNetProfit(log);
            dailyExpense += _rowExpenseFeePlusTransport(log);
          }
          int logCount = dailyLogs.length;

          final screenWidth = MediaQuery.of(context).size.width;
          final isTablet = screenWidth > 600;
          final horizontalPadding = isTablet ? 24.0 : 20.0;
          final verticalPadding = isTablet ? 18.0 : 16.0;
          final iconSize = isTablet ? 22.0 : 20.0;
          final spacing = isTablet ? 14.0 : 12.0;
          final innerSpacing = isTablet ? 6.0 : 4.0;

          return Container(
            key: isToday ? _todayKey : null,
            decoration: const BoxDecoration(
              color: Color(0xFF1F222A),
              border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyLogListPage(
                      dateStr: dateStr,
                      dateTitle: '근무일자: $dateStr',
                    ),
                  ),
                ).then((_) => _loadMonthData());
              },
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                child: Row(
                  children: [
                    Icon(Icons.contact_mail, color: isToday ? const Color(0xFFFFC700) : Colors.white, size: iconSize),
                    SizedBox(width: spacing),
                    Text("${day.toString().padLeft(2, '0')} ($dayOfWeek)", style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: isToday ? const Color(0xFFFFC700) : Colors.white)),
                    SizedBox(width: spacing + 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${logCount}건", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
                          SizedBox(height: innerSpacing),
                          Row(
                            children: [
                              const Text("순익 : ", style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                              Text("₩${NumberFormat('#,###').format(dailyNetProfit)}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            const Text("수입 : ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                            Text("₩${NumberFormat('#,###').format(dailyIncome)}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.lightBlueAccent)),
                          ],
                        ),
                        SizedBox(height: innerSpacing),
                        Row(
                          children: [
                            const Text("지출 : ", style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                            Text("-₩${NumberFormat('#,###').format(dailyExpense)}", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFF5252))),
                          ],
                        ),
                      ],
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
    final itemSpacing = isTablet ? 20.0 : 16.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
      color: const Color(0xFF1F222A),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("[ 월간 합계 ]", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(height: spacing),
                Row(
                  children: [
                    const Text("순익 : ", style: TextStyle(color: Color(0xFFFFC700), fontSize: 14)),
                    Text("₩${NumberFormat('#,###').format(_totalNet)}", style: TextStyle(color: const Color(0xFFFFC700), fontSize: valueFontSize, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text("${_totalCount}건", style: TextStyle(color: Colors.white, fontSize: infoFontSize)),
                    SizedBox(width: itemSpacing),
                    const Text("수입 : ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                    Text("₩${NumberFormat('#,###').format(_totalGross)}", style: TextStyle(color: Colors.lightBlueAccent, fontSize: infoFontSize)),
                  ],
                ),
                SizedBox(height: spacing),
                Row(
                  children: [
                    const Text("지출 : ", style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                    Text("-₩${NumberFormat('#,###').format(_totalExpenses)}", style: TextStyle(color: const Color(0xFFFF5252), fontSize: infoFontSize)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DailyLogListPage extends StatefulWidget {
  final String dateStr;
  final String dateTitle;
  /// 저장 직후 이 화면에서 스낵을 띄울 때 (작성 화면에서 저장+스낵 후 pop 하면 매니저/오버레이가 꼬일 수 있음)
  final String? snackMessage;

  const DailyLogListPage({
    super.key,
    required this.dateStr,
    required this.dateTitle,
    this.snackMessage,
  });

  @override
  State<DailyLogListPage> createState() => _DailyLogListPageState();
}

class _DailyLogListPageState extends State<DailyLogListPage> {
  List<Map<String, dynamic>> _dailyLogs = [];
  bool _isLoading = true;
  final ScreenshotController _shareScreenshotController = ScreenshotController();

  int _totalCount = 0;
  int _totalIncomeSum = 0;
  int _totalNetProfitSum = 0;
  int _totalExpenseSum = 0;

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    final msg = widget.snackMessage?.trim();
    if (msg != null && msg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final rawLogs = await DriveLogDatabase.instance.getLogsForWorkDate(widget.dateStr);
      final logs = List<Map<String, dynamic>>.from(rawLogs);
      
      int incomeSum = 0;
      int netProfitSum = 0;
      int expenseSum = 0;
      for (var log in logs) {
        incomeSum += _rowIncomePlusTip(log);
        netProfitSum += _rowNetProfit(log);
        expenseSum += _rowExpenseFeePlusTransport(log);
      }

      if (!mounted) return;
      setState(() {
        _dailyLogs = logs;
        _totalCount = logs.length;
        _totalIncomeSum = incomeSum;
        _totalNetProfitSum = netProfitSum;
        _totalExpenseSum = expenseSum;
      });
    } catch (e, st) {
      debugPrint('DailyLogListPage load error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("상세 목록을 불러오는 중 오류가 발생했습니다.")),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _shareDetailAsImage() async {
    if (!mounted || _isLoading) return;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('웹에서는 공유를 지원하지 않습니다.')),
      );
      return;
    }

    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;

      final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
      final bytes = await _shareScreenshotController.capture(
        delay: const Duration(milliseconds: 100),
        pixelRatio: pixelRatio,
      );

      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지를 만들 수 없습니다. 잠시 후 다시 시도해 주세요.')),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final safe = widget.dateStr.replaceAll(RegExp(r'[^0-9\-]'), '');
      final file = File(p.join(dir.path, 'dbros_daily_$safe.png'));
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          subject: widget.dateTitle,
          title: widget.dateTitle,
          text: widget.dateTitle,
        ),
      );
    } catch (e, st) {
      debugPrint('DailyLogListPage share error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유에 실패했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final titleFontSize = isTablet ? 18.0 : 16.0;

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F222A),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: Text(widget.dateTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleFontSize)),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _shareDetailAsImage,
              child: Text(
                '공유',
                style: TextStyle(
                  color: const Color(0xFFFFC700),
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 15 : 14,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
          : Screenshot(
              controller: _shareScreenshotController,
              child: ColoredBox(
                color: const Color(0xFF121418),
                child: Column(
                  children: [
                    Expanded(child: _buildList()),
                    _buildDailySummaryFooter(),
                  ],
                ),
              ),
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => DriveLogForm(initialDate: widget.dateStr))).then((_) => _loadData());
            } else if (index == 1) {
              Navigator.pop(context);
            } else {
              Navigator.pushAndRemoveUntil(
                context, 
                MaterialPageRoute(builder: (_) => MainWrapper(initialIndex: index)), 
                (route) => false
              );
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), activeIcon: Icon(Icons.home), label: "홈"),
            BottomNavigationBarItem(icon: Icon(Icons.list_alt), activeIcon: Icon(Icons.list_alt), label: "목록"),
            BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: "작성"),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), activeIcon: Icon(Icons.bar_chart), label: "통계"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: "설정"),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _dailyLogs.length,
      itemBuilder: (context, index) {
        final log = _dailyLogs[index];
        final String time = log['drive_time'].toString().replaceFirst(':', '시 ') + "분";
        
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth > 600;
        final horizontalPadding = isTablet ? 24.0 : 20.0;
        final verticalPadding = isTablet ? 18.0 : 16.0;
        final timeFontSize = isTablet ? 16.0 : 15.0;
        final programFontSize = isTablet ? 15.0 : 14.0;
        final incomeFontSize = isTablet ? 15.0 : 14.0;
        final locationFontSize = isTablet ? 14.0 : 13.0;
        final spacing = isTablet ? 18.0 : 16.0;
        final innerSpacing = isTablet ? 14.0 : 12.0;
        
        return Dismissible(
          key: Key(log['id'].toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: EdgeInsets.only(right: horizontalPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete, color: Colors.white, size: isTablet ? 26 : 24),
                SizedBox(height: 4),
                Text("삭제", style: TextStyle(color: Colors.white, fontSize: isTablet ? 13 : 12)),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1F222A),
                title: const Text("운행일지 삭제", style: TextStyle(color: Colors.white)),
                content: Text("이 운행일지를 삭제하시겠습니까?\n\n$time ${log['program']}", style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("취소", style: TextStyle(color: Color(0xFF6E717C))),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("삭제", style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (direction) async {
            await DriveLogDatabase.instance.deleteLog(log['id']);
            _loadData();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("운행일지가 삭제되었습니다."),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => DriveLogForm(existingLog: log))).then((_) => _loadData());
            },
            child: Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5))),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text("[ $time ]", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: timeFontSize)),
                          SizedBox(width: innerSpacing),
                          Text(log['program'], style: TextStyle(color: Colors.white70, fontSize: programFontSize)),
                        ],
                      ),
                      Builder(
                        builder: (context) {
                          final g = _toInt(log['gross_fare']);
                          final tip = _toInt(log['waypoint_tip']);
                          final revenue = g + tip;
                          return Row(
                            children: [
                              const Text("수입 : ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                              Text(
                                "₩${NumberFormat('#,###').format(revenue)}",
                                style: TextStyle(color: Colors.lightBlueAccent, fontSize: incomeFontSize, fontWeight: FontWeight.bold),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: spacing),
                  Builder(
                    builder: (context) {
                      final fullStart = log['start_location']?.toString().trim();
                      final fullEnd = log['end_location']?.toString().trim();
                      final fullWp = log['waypoint']?.toString().trim();
                      final locStyle = TextStyle(color: const Color(0xFFFFC700), fontSize: locationFontSize);
                      final arrowIcon = Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward, color: Colors.white54, size: isTablet ? 14 : 12),
                      );
                      Widget segment(String? full, String placeholder, {TextAlign align = TextAlign.start}) {
                        final t = (full != null && full.isNotEmpty) ? full : placeholder;
                        return Text(
                          t,
                          style: locStyle,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                        );
                      }

                      final hasWp = fullWp != null && fullWp.isNotEmpty;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 1, child: segment(fullStart, '출발지')),
                          arrowIcon,
                          if (hasWp) ...[
                            Expanded(flex: 1, child: segment(fullWp, '경유', align: TextAlign.center)),
                            arrowIcon,
                          ],
                          Expanded(flex: 1, child: segment(fullEnd, '도착지', align: TextAlign.end)),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: spacing / 2),
                  if ((log['memo'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      (log['memo'] ?? '').toString().trim(),
                      style: TextStyle(color: Colors.white70, fontSize: locationFontSize - 1),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildDailySummaryFooter() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 20.0 : 16.0;
    final valueFontSize = isTablet ? 15.0 : 14.0;
    final infoFontSize = isTablet ? 14.0 : 13.0;
    final spacing = isTablet ? 8.0 : 6.0;
    final itemSpacing = isTablet ? 20.0 : 16.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
      color: const Color(0xFF1F222A),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("[ 일일 합계 ]", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(height: spacing),
                Row(
                  children: [
                    Text("순익 : ", style: TextStyle(color: Colors.blueAccent.shade200, fontSize: 14)),
                    Text(
                      "₩${NumberFormat('#,###').format(_totalNetProfitSum)}",
                      style: TextStyle(color: Colors.blueAccent.shade200, fontSize: valueFontSize, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text("${_totalCount}건", style: TextStyle(color: Colors.white, fontSize: infoFontSize)),
                    SizedBox(width: itemSpacing),
                    const Text("수입 : ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                    Text(
                      "₩${NumberFormat('#,###').format(_totalIncomeSum)}",
                      style: TextStyle(color: Colors.lightBlueAccent, fontSize: infoFontSize),
                    ),
                  ],
                ),
                SizedBox(height: spacing),
                Row(
                  children: [
                    const Text("지출 : ", style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                    Text(
                      "-₩${NumberFormat('#,###').format(_totalExpenseSum)}",
                      style: TextStyle(color: const Color(0xFFFF5252), fontSize: infoFontSize),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

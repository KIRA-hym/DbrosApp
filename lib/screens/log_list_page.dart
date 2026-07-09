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
import 'stats_page.dart' show StatsRouteMapPage, TripSegment;
import '../config/feature_flags.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) '../utils/maps_web_stub.dart';
import '../utils/responsive_layout.dart';
import '../utils/snackbar_utils.dart';
import '../utils/work_date_utils.dart';
import '../widgets/app_glass_dialog.dart';
import '../widgets/responsive_body.dart';
import '../widgets/drive_log_source_chip.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../providers/guide_provider.dart';
import '../widgets/guide_content_widget.dart';

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
  
  final GlobalKey _keyMonthHeader = GlobalKey();
  final GlobalKey _keyShareButton = GlobalKey();
  final GlobalKey _keyDailyList = GlobalKey();
  final GlobalKey _keyMonthlySummary = GlobalKey();

  final ScreenshotController _monthShareScreenshotController = ScreenshotController();
  String? _masterDetailDate;
  /// 마스터-디테일 우측 패널 강제 갱신(하루 삭제·월 데이터 reload 등).
  int _detailRevision = 0;
  bool? _wasExpanded;

  /// 펼침 마스터-디테일 기본 선택: 보는 달에 **오늘 근무일**이 있으면 그 날짜, 없으면 null(우측 빈 패널).
  String? _initialMasterDetailDateInFocusedMonth() {
    final workYmd = WorkDateUtils.effectiveWorkDateYmd();
    final parsed = DateTime.tryParse(workYmd);
    if (parsed == null) return null;
    if (parsed.year == _focusedMonth.year && parsed.month == _focusedMonth.month) {
      return workYmd;
    }
    return null;
  }

  Widget _buildMasterDetailAmountRow({
    required String label,
    required int amount,
    required Color labelColor,
    required Color valueColor,
    required String prefix,
    bool valueBold = false,
    TextAlign valueAlign = TextAlign.start,
  }) {
    return Container(
      alignment: valueAlign == TextAlign.end ? Alignment.centerRight : Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$label : ', style: TextStyle(color: labelColor, fontSize: 13)),
              TextSpan(
                text: '$prefix${NumberFormat('#,###').format(amount)}',
                style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight: valueBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMasterDetailDayTile({
    required int day,
    required String dayOfWeek,
    required bool isToday,
    required int logCount,
    required int dailyIncome,
    required int dailyExpense,
    required int dailyNetProfit,
    required double iconSize,
    required double spacing,
    required double innerSpacing,
    required String dateStr,
    required List<Map<String, dynamic>> dailyLogs,
  }) {
    final dayColor = isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.contact_mail, color: dayColor, size: iconSize),
        SizedBox(width: spacing),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${day.toString().padLeft(2, '0')} ($dayOfWeek)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: dayColor,
                                  fontSize: 13,
                                ),
                          ),
                        ),
                        SizedBox(width: spacing),
                        Text('$logCount건', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                        TextSpan(
                          text: '₩${NumberFormat('#,###').format(dailyIncome)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.lightBlueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              SizedBox(height: innerSpacing),
              Row(
                children: [
                  Expanded(
                    child: _buildMasterDetailAmountRow(
                      label: '순익',
                      amount: dailyNetProfit,
                      labelColor: Theme.of(context).primaryColor,
                      valueColor: Theme.of(context).primaryColor,
                      prefix: '₩',
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: _buildMasterDetailAmountRow(
                      label: '지출',
                      amount: dailyExpense,
                      labelColor: const Color(0xFFFF5252),
                      valueColor: const Color(0xFFFF5252),
                      prefix: '-₩',
                      valueAlign: TextAlign.end,
                    ),
                  ),
                ],
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
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color!,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '[ 월간 합계 ]',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$_totalCount건', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                      SizedBox(width: 10),
                      Text('수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                      Text(
                        '₩${NumberFormat('#,###').format(_totalGross)}',
                        style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '순익 : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                        TextSpan(text: '₩${NumberFormat('#,###').format(_totalNet)}', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                        TextSpan(text: '-₩${NumberFormat('#,###').format(_totalExpenses)}', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  @override
  void initState() {
    super.initState();
    _loadMonthData();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guideProvider = Provider.of<GuideProvider>(context, listen: false);
      guideProvider.addListener(_onGuideRequested);
      if (guideProvider.pendingGuideTarget == 'list') {
        _startGuideWhenReady();
      }
    });
  }

  void _startGuideWhenReady() async {
    while (_isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _showListGuide();
  }

  void _onGuideRequested() {
    if (!mounted) return;
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    if (guideProvider.pendingGuideTarget == 'list') {
      _startGuideWhenReady();
    }
  }

  void _showListGuide() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.clearGuide();

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "monthHeader",
        keyTarget: _keyMonthHeader,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "월간 일지 이동",
                description: "좌우 화살표를 눌러 이전/다음 달의 운행 기록을 확인할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "shareList",
        keyTarget: _keyShareButton,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "월간 기록 공유",
                description: "현재 보고 있는 월간 운행 내역 전체를 이미지로 캡처해서 카카오톡 등으로 공유할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
    ];

    targets.add(
      TargetFocus(
        identify: "dailyList",
        keyTarget: _keyDailyList,
        shape: ShapeLightFocus.RRect,
        radius: 8.0,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "상세 진입 및 스와이프 삭제",
                description: "날짜를 터치하면 해당 일자의 상세 내역을 볼 수 있고, 항목을 왼쪽으로 스와이프하면 그 날의 기록을 모두 삭제할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
    );

    targets.add(
      TargetFocus(
        identify: "monthlySummary",
        keyTarget: _keyMonthlySummary,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "월간 수입/지출 요약",
                description: "한 달 동안의 총 운행 건수와 수입, 지출, 순수익을 한눈에 파악하세요!",
                controller: controller,
                isLast: true,
              );
            },
          ),
        ],
      ),
    );

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "건너뛰기",
      paddingFocus: 10,
      opacityShadow: 0.8,
    ).show(context: context);
  }

  @override
  void dispose() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.removeListener(_onGuideRequested);
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
      _syncMasterDetailDateInState();
      _detailRevision++;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Removed duplicate guide trigger
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
    final isExpanded = ResponsiveLayout.isExpanded(context);
    
    if (_wasExpanded == true && !isExpanded && _masterDetailDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final date = _masterDetailDate!;
        _masterDetailDate = null;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DailyLogListPage(
              dateStr: date,
              dateTitle: date,
            ),
          ),
        ).then((returnedDate) {
          if (returnedDate is String) {
            setState(() => _masterDetailDate = returnedDate);
          }
          _loadMonthData();
        });
      });
    }

    if (isExpanded && _masterDetailDate == null && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final initial = _initialMasterDetailDateInFocusedMonth();
        if (initial != null) {
          setState(() => _masterDetailDate = initial);
        }
      });
    }
    
    _wasExpanded = isExpanded;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "운행 일지 목록",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
        ),
        backgroundColor: Theme.of(context).cardTheme.color!,
        actions: [
          if (!_isLoading)
            TextButton(
              key: _keyShareButton,
              onPressed: _shareMonthListAsImage,
              child: Text(
                '공유',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: ResponsiveLayout.isFoldOrTablet(context) ? 15 : 14,
                ),
              ),
            ),
        ],
      ),
      body: isExpanded
          ? _buildExpandedMasterDetailBody()
          : ResponsiveBody(
              child: Column(
                children: [
                  _buildMonthHeader(),
                  Expanded(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: _isLoading
                          ? Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
                          : Stack(
                              children: [
                                Opacity(
                                  opacity: _isScrolled ? 1.0 : 0.0,
                                  child: _buildDailyList(
                                    selectedDate: _masterDetailDate,
                                    masterDetailMode: false,
                                  ),
                                ),
                                if (_groupedLogs.isNotEmpty)
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 70,
                                    child: IgnorePointer(
                                      child: Container(key: _keyDailyList),
                                    ),
                                  ),
                              ],
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
              ? Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 1,
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  _buildDailyList(
                                    masterDetailMode: true,
                                    selectedDate: selected,
                                    onSelectDate: (d) => setState(() => _masterDetailDate = d),
                                  ),
                                  if (_groupedLogs.isNotEmpty)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      height: 70, // 대략적인 리스트 아이템 높이
                                      child: IgnorePointer(
                                        child: Container(key: _keyDailyList),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _buildMasterDetailMonthlySummary(compact: true),
                          ],
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                    Expanded(
                      flex: 1,
                      child: selected == null
                          ? Center(
                              child: Text(
                                '왼쪽에서 날짜를 선택하세요',
                                style: TextStyle(color: Color(0xFF6E717C)),
                              ),
                            )
                          : DailyLogListPage(
                              key: ValueKey('${selected}_$_detailRevision'),
                              dateStr: selected,
                              dateTitle: selected,
                              embedded: true,
                              onLogsChanged: _loadMonthData,
                              onDateChanged: (newDate) {
                                final parsed = DateTime.tryParse(newDate);
                                if (parsed != null) {
                                  if (parsed.year != _focusedMonth.year || parsed.month != _focusedMonth.month) {
                                    _focusedMonth = DateTime(parsed.year, parsed.month, 1);
                                    _loadMonthData();
                                  }
                                }
                                setState(() => _masterDetailDate = newDate);
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMonthHeader() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 12.0 : 8.0;
    final iconSize = isTablet ? 28.0 : 24.0;

    return Container(
      key: _keyMonthHeader,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color!,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_left, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: iconSize), 
            onPressed: () => _changeMonth(-1),
            constraints: BoxConstraints(minWidth: iconSize + 8, minHeight: iconSize + 8),
          ),
          SizedBox(width: isTablet ? 20 : 16),
          Text(
            DateFormat('yyyy년 MM월').format(_focusedMonth), 
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white))
          ),
          SizedBox(width: isTablet ? 20 : 16),
          IconButton(
            icon: Icon(Icons.arrow_right, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: iconSize), 
            onPressed: () => _changeMonth(1),
            constraints: BoxConstraints(minWidth: iconSize + 8, minHeight: iconSize + 8),
          ),
        ],
      ),
    );
  }

  void _openDailyRouteMap(String dateStr, List<Map<String, dynamic>> logs) {
    if (!kMapFeaturesEnabled) return;

    final segments = <TripSegment>[];
    for (final log in logs) {
      final startLat = (log['start_lat'] as num?)?.toDouble();
      final startLng = (log['start_lng'] as num?)?.toDouble();
      final endLat = (log['end_lat'] as num?)?.toDouble();
      final endLng = (log['end_lng'] as num?)?.toDouble();
      final time = (log['drive_time'] ?? '').toString();
      final program = (log['program'] ?? '').toString();

      final startLoc = (log['start_location'] ?? '').toString();
      final endLoc = (log['end_location'] ?? '').toString();

      if (startLat != null && startLng != null && endLat != null && endLng != null) {
        segments.add(
          TripSegment(
            start: LatLng(startLat, startLng),
            end: LatLng(endLat, endLng),
            startSnippet: '$program · $time\n(${startLoc.isNotEmpty ? startLoc : '주소 정보 없음'})',
            endSnippet: '$program · $time\n(${endLoc.isNotEmpty ? endLoc : '주소 정보 없음'})',
          ),
        );
      }
    }

    if (segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('해당 일자에 표시할 좌표 데이터가 없습니다.')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatsRouteMapPage(
          periodLabel: '일간',
          dateLabel: '근무일자: $dateStr',
          segments: segments,
        ),
      ),
    );
  }

  Widget _buildDailyList({
    bool masterDetailMode = false,
    String? selectedDate,
    void Function(String dateStr)? onSelectDate,
  }) {
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
            final isTablet = ResponsiveLayout.isFoldOrTablet(context);
            final horizontalPadding = isTablet ? 24.0 : 20.0;
            final iconSize = isTablet ? 22.0 : 20.0;
            final isSelected = selectedDate == dateStr;

            return Container(
              decoration: BoxDecoration(
                color: isSelected ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4)) : Theme.of(context).cardTheme.color!,
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                leading: Icon(Icons.label, color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7), size: iconSize),
                title: Text("${day.toString().padLeft(2, '0')} ($dayOfWeek)", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7), fontWeight: FontWeight.bold)),
                trailing: Text("<일지 입력>", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
                onTap: () {
                  if (masterDetailMode && onSelectDate != null) {
                    onSelectDate(dateStr);
                    return;
                  }
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

          final isTablet = ResponsiveLayout.isFoldOrTablet(context);
          final horizontalPadding = isTablet ? 24.0 : 20.0;
          final verticalPadding = isTablet ? 18.0 : 16.0;
          final iconSize = isTablet ? 22.0 : 20.0;
          final spacing = isTablet ? 16.0 : 12.0;
          final innerSpacing = isTablet ? 6.0 : 4.0;
          final isSelected = selectedDate == dateStr;
                 return Container(
            decoration: BoxDecoration(
              color: isSelected ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4)) : Theme.of(context).cardTheme.color!,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
            ),
            child: Dismissible(
              key: Key("day_$dateStr"),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(right: horizontalPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: isTablet ? 26 : 24),
                    SizedBox(height: 4),
                    Text("삭제", style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: isTablet ? 13 : 12)),
                  ],
                ),
              ),
              confirmDismiss: (direction) async {
                return await AppGlassDialog.show<bool>(
                  context: context,
                  dialog: AppGlassDialog(
                    icon: Icons.delete_outline,
                    title: '하루 일지 삭제',
                    content: '$dateStr의 운행일지 $logCount건을 모두 삭제하시겠습니까?',
                    actions: [
                      Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx, false))),
                      Builder(builder: (ctx) => GlassDialogDestructiveButton(onPressed: () => Navigator.pop(ctx, true))),
                    ],
                  ),
                );
              },
              onDismissed: (direction) async {
                for (var log in dailyLogs) {
                  await DriveLogDatabase.instance.deleteLog(log['id']);
                }
                _loadMonthData();

                if (!mounted) return;
                showDbrosSnackBar(
                  context,
                  "$dateStr의 모든 운행일지가 삭제되었습니다.",
                  backgroundColor: Colors.red,
                );
              },
              child: InkWell(
                onTap: () {
                  if (masterDetailMode && onSelectDate != null) {
                    onSelectDate(dateStr);
                    return;
                  }
                  Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DailyLogListPage(
                        dateStr: dateStr,
                        dateTitle: dateStr,
                      ),
                    ),
                  ).then((result) {
                    _loadMonthData();
                    if (!mounted) return;
                    if (result != null && ResponsiveLayout.isExpanded(context)) {
                      setState(() => _masterDetailDate = result);
                    }
                  });
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                  child: masterDetailMode
                      ? _buildMasterDetailDayTile(
                          day: day,
                          dayOfWeek: dayOfWeek,
                          isToday: isToday,
                          logCount: logCount,
                          dailyIncome: dailyIncome,
                          dailyExpense: dailyExpense,
                          dailyNetProfit: dailyNetProfit,
                          iconSize: iconSize,
                          spacing: spacing,
                          innerSpacing: innerSpacing,
                          dateStr: dateStr,
                          dailyLogs: dailyLogs,
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.contact_mail, color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: iconSize),
                            SizedBox(width: spacing),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                '${day.toString().padLeft(2, '0')} ($dayOfWeek)',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                      color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                                                      fontSize: 13,
                                                    ),
                                              ),
                                            ),
                                            SizedBox(width: spacing),
                                            Text('$logCount건', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(text: '수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                                            TextSpan(
                                              text: '₩${NumberFormat('#,###').format(dailyIncome)}',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Colors.lightBlueAccent,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: innerSpacing),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildMasterDetailAmountRow(
                                          label: '순익',
                                          amount: dailyNetProfit,
                                          labelColor: Theme.of(context).primaryColor,
                                          valueColor: Theme.of(context).primaryColor,
                                          prefix: '₩',
                                        ),
                                      ),
                                      SizedBox(width: spacing),
                                      Expanded(
                                        child: _buildMasterDetailAmountRow(
                                          label: '지출',
                                          amount: dailyExpense,
                                          labelColor: const Color(0xFFFF5252),
                                          valueColor: const Color(0xFFFF5252),
                                          prefix: '-₩',
                                          valueAlign: TextAlign.end,
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
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMonthlySummaryFooter() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 20.0 : 16.0;
    final infoFontSize = isTablet ? 14.0 : 13.0;
    final spacing = isTablet ? 8.0 : 6.0;
    final itemSpacing = isTablet ? 20.0 : 16.0;

    return Container(
      key: _keyMonthlySummary,
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
      color: Theme.of(context).cardTheme.color!,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '[ 월간 합계 ]',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_totalCount건', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: infoFontSize)),
                        SizedBox(width: 12),
                        Text('수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                        Text(
                          '₩${NumberFormat('#,###').format(_totalGross)}',
                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: infoFontSize, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '순익 : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                          TextSpan(text: '₩${NumberFormat('#,###').format(_totalNet)}', style: TextStyle(color: Color(0xFFFFC700), fontSize: infoFontSize)),
                        ],
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                          TextSpan(text: '-₩${NumberFormat('#,###').format(_totalExpenses)}', style: TextStyle(color: const Color(0xFFFF5252), fontSize: infoFontSize)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareMonthListAsImage() async {
    if (!mounted || _isLoading) return;
    if (ResponsiveLayout.isExpanded(context)) {
      showDbrosSnackBar(context, '폰을 접은 상태에서만 공유 기능이 가능합니다.');
      return;
    }
    if (kIsWeb) {
      showDbrosSnackBar(context, '웹에서는 공유를 지원하지 않습니다.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
      final captureWidth = MediaQuery.sizeOf(context).width;
      final theme = Theme.of(context);
      final ymTitle = DateFormat('yyyy년 MM월').format(_focusedMonth);
      final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
      final now = DateTime.now();

      final captureRoot = Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Theme(
          data: theme,
          child: SizedBox(
            width: captureWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Theme.of(context).cardTheme.color!,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  child: Text(
                    '운행 일지 목록  $ymTitle',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                    ),
                  ),
                ),
                ...List<Widget>.generate(daysInMonth, (index) {
                  final day = index + 1;
                  final currentDate = DateTime(_focusedMonth.year, _focusedMonth.month, day);
                  final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
                  final dayOfWeek = DateFormat('E', 'ko_KR').format(currentDate);
                  final isToday = currentDate.year == now.year &&
                      currentDate.month == now.month &&
                      currentDate.day == now.day;
                  final dailyLogs = _groupedLogs[dateStr] ?? [];
                  return _buildMonthShareDayRow(
                    theme,
                    captureWidth,
                    day,
                    dayOfWeek,
                    isToday,
                    dailyLogs,
                  );
                }),
                _buildMonthShareFooter(theme, captureWidth),
              ],
            ),
          ),
        ),
      );

      final bytes = await _monthShareScreenshotController.captureFromLongWidget(
        captureRoot,
        context: context,
        delay: const Duration(milliseconds: 1200),
        pixelRatio: pixelRatio,
        constraints: BoxConstraints(
          maxWidth: captureWidth,
          maxHeight: double.maxFinite,
        ),
      );

      if (!mounted) return;
      if (bytes.isEmpty) {
        showDbrosSnackBar(context, '이미지를 만들 수 없습니다. 잠시 후 다시 시도해 주세요.');
        return;
      }

      final dir = await getTemporaryDirectory();
      if (!mounted) return;
      final safe = DateFormat('yyyyMM').format(_focusedMonth);
      final file = File(p.join(dir.path, 'dbros_monthly_$safe.png'));
      await file.writeAsBytes(bytes, flush: true);

      final title = '운행 일지 목록 $ymTitle';
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          subject: title,
          title: title,
          text: title,
        ),
      );
    } catch (e, st) {
      debugPrint('LogListPage month share error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      showDbrosSnackBar(context, '공유에 실패했습니다: $e');
    }
  }

  Widget _buildMonthShareDayRow(
    ThemeData theme,
    double width,
    int day,
    String dayOfWeek,
    bool isToday,
    List<Map<String, dynamic>> dailyLogs,
  ) {
    final isTablet = width > 600;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 18.0 : 16.0;
    final iconSize = isTablet ? 22.0 : 20.0;
    final spacing = isTablet ? 14.0 : 12.0;
    final innerSpacing = isTablet ? 6.0 : 4.0;

    if (dailyLogs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding * 0.75),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.label, color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey), size: iconSize),
                  SizedBox(width: spacing),
                  Text(
                    '${day.toString().padLeft(2, '0')} ($dayOfWeek)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7),
                    ),
                  ),
                ],
              ),
              Text('<일지 입력>', style: theme.textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
            ],
          ),
        ),
      );
    }

    var dailyIncome = 0;
    var dailyNetProfit = 0;
    var dailyExpense = 0;
    for (final log in dailyLogs) {
      dailyIncome += _rowIncomePlusTip(log);
      dailyNetProfit += _rowNetProfit(log);
      dailyExpense += _rowExpenseFeePlusTransport(log);
    }
    final logCount = dailyLogs.length;
    const double dayLabelReserve = 80;
    const double rightBlockReserve = 142;
    final double middleW = (width -
            horizontalPadding * 2 -
            iconSize -
            spacing -
            dayLabelReserve -
            spacing -
            rightBlockReserve)
        .clamp(72.0, 2000.0);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color!,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Row(
          children: [
            Icon(Icons.contact_mail, color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: iconSize),
            SizedBox(width: spacing),
            Text(
              '${day.toString().padLeft(2, '0')} ($dayOfWeek)',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isToday ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
              ),
            ),
            SizedBox(width: spacing + 8),
            SizedBox(
              width: middleW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$logCount건', style: theme.textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white))),
                  SizedBox(height: innerSpacing),
                  Row(
                    children: [
                      Text(
                        '순익 : ₩${NumberFormat('#,###').format(dailyNetProfit)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    Text('수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                    Text(
                      '₩${NumberFormat('#,###').format(dailyIncome)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.lightBlueAccent),
                    ),
                  ],
                ),
                SizedBox(height: innerSpacing),
                Row(
                  children: [
                    Text('지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                    Text(
                      '-₩${NumberFormat('#,###').format(dailyExpense)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFF5252)),
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

  Widget _buildMonthShareFooter(ThemeData theme, double screenWidth) {
    final isTablet = screenWidth > 600;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 20.0 : 16.0;
    final valueFontSize = isTablet ? 15.0 : 14.0;
    final infoFontSize = isTablet ? 14.0 : 13.0;
    final spacing = isTablet ? 8.0 : 6.0;
    final itemSpacing = isTablet ? 20.0 : 16.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: horizontalPadding),
      color: Theme.of(context).cardTheme.color!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '[ 월간 합계 ]',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$_totalCount건', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: infoFontSize)),
                      SizedBox(width: 12),
                      Text('순익 : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 14)),
                      Text(
                        '₩${NumberFormat('#,###').format(_totalNet)}',
                        style: TextStyle(color: Theme.of(context).primaryColor, fontSize: valueFontSize, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                        TextSpan(text: '₩${NumberFormat('#,###').format(_totalGross)}', style: TextStyle(color: Colors.lightBlueAccent, fontSize: infoFontSize)),
                      ],
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                        TextSpan(text: '-₩${NumberFormat('#,###').format(_totalExpenses)}', style: TextStyle(color: const Color(0xFFFF5252), fontSize: infoFontSize)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
class _DailyDetailShareLayout {
  const _DailyDetailShareLayout({
    required this.isTablet,
    required this.rowHorizontalPadding,
    required this.rowVerticalPadding,
    required this.timeFontSize,
    required this.programFontSize,
    required this.incomeFontSize,
    required this.locationFontSize,
    required this.rowSpacing,
    required this.innerSpacing,
    required this.footerHorizontalPadding,
    required this.footerVerticalPadding,
    required this.footerValueFontSize,
    required this.footerInfoFontSize,
    required this.footerSpacing,
    required this.footerItemSpacing,
  });

  final bool isTablet;
  final double rowHorizontalPadding;
  final double rowVerticalPadding;
  final double timeFontSize;
  final double programFontSize;
  final double incomeFontSize;
  final double locationFontSize;
  final double rowSpacing;
  final double innerSpacing;
  final double footerHorizontalPadding;
  final double footerVerticalPadding;
  final double footerValueFontSize;
  final double footerInfoFontSize;
  final double footerSpacing;
  final double footerItemSpacing;

  factory _DailyDetailShareLayout.fromWidth(double screenWidth) {
    final isTablet = screenWidth > 600;
    return _DailyDetailShareLayout(
      isTablet: isTablet,
      rowHorizontalPadding: isTablet ? 24.0 : 20.0,
      rowVerticalPadding: isTablet ? 18.0 : 16.0,
      timeFontSize: isTablet ? 16.0 : 15.0,
      programFontSize: isTablet ? 15.0 : 14.0,
      incomeFontSize: isTablet ? 15.0 : 14.0,
      locationFontSize: isTablet ? 14.0 : 13.0,
      rowSpacing: isTablet ? 18.0 : 16.0,
      innerSpacing: isTablet ? 14.0 : 12.0,
      footerHorizontalPadding: isTablet ? 24.0 : 20.0,
      footerVerticalPadding: isTablet ? 20.0 : 16.0,
      footerValueFontSize: isTablet ? 15.0 : 14.0,
      footerInfoFontSize: isTablet ? 14.0 : 13.0,
      footerSpacing: isTablet ? 8.0 : 6.0,
      footerItemSpacing: isTablet ? 20.0 : 16.0,
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
    this.embedded = false,
    this.onLogsChanged,
    this.onDateChanged,
  });

  /// 목록 마스터-디테일 오른쪽 패널용.
  final bool embedded;
  final VoidCallback? onLogsChanged;
  final ValueChanged<String>? onDateChanged;

  @override
  State<DailyLogListPage> createState() => _DailyLogListPageState();
}

class _DailyLogListPageState extends State<DailyLogListPage> {
  List<Map<String, dynamic>> _dailyLogs = [];
  bool _isLoading = true;
  bool _poppingForExpandedLayout = false;
  final ScreenshotController _shareScreenshotController = ScreenshotController();

  final GlobalKey _keyDailyDateNav = GlobalKey();
  final GlobalKey _keyDailyMapBtn = GlobalKey();
  final GlobalKey _keyDailyItem = GlobalKey();
  final GlobalKey _keyDailyShareBtn = GlobalKey();

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

  late String _currentDateStr;
  late String _currentDateTitle;

  @override
  void initState() {
    super.initState();
    _currentDateStr = widget.dateStr;
    _currentDateTitle = widget.dateTitle;
    _loadData();
    final msg = widget.snackMessage?.trim();
    if (msg != null && msg.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDbrosSnackBar(context, msg);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guideProvider = Provider.of<GuideProvider>(context, listen: false);
      guideProvider.addListener(_onGuideRequested);
      if (guideProvider.pendingGuideTarget == 'detail') {
        _startGuideWhenReady();
      }
    });
  }

  void _startGuideWhenReady() async {
    while (_isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _showDetailGuide();
  }

  void _onGuideRequested() {
    if (!mounted) return;
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    if (guideProvider.pendingGuideTarget == 'detail') {
      _startGuideWhenReady();
    }
  }

  void _showDetailGuide() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.clearGuide();

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "dailyDateNav",
        keyTarget: _keyDailyDateNav,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "다른 날짜 보기",
                description: "상단의 화살표를 눌러 이전 날짜나 다음 날짜의 운행 일지로 바로 이동할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
    ];

    final showMapBtn = kMapFeaturesEnabled && _dailyLogs.any((log) => log['start_lat'] != null);
    if (kMapFeaturesEnabled) {
      targets.add(
        TargetFocus(
          identify: "dailyMapBtn",
          keyTarget: _keyDailyMapBtn,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "일일 동선 맵",
                  description: "지도 아이콘을 누르면 그날 하루 동안 이동한 전체 경로를 지도에서 한눈에 볼 수 있어요! (GPS 데이터가 없으면 비활성화됩니다)",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    targets.add(
      TargetFocus(
        identify: "dailyItem",
        keyTarget: _keyDailyItem,
        shape: ShapeLightFocus.RRect,
        radius: 8.0,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "일지 수정 및 삭제",
                description: "개별 항목을 터치해 수정하거나, 왼쪽으로 스와이프해서 불필요한 일지를 개별 삭제할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
    );

    targets.add(
      TargetFocus(
        identify: "dailyShareBtn",
        keyTarget: _keyDailyShareBtn,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return GuideContentWidget(
                title: "하루 기록 공유",
                description: "하루 동안의 운행 내역과 수입/지출 합계를 캡처하여 다른 사람에게 공유할 수 있어요.",
                controller: controller,
                isLast: true,
              );
            },
          ),
        ],
      ),
    );

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "건너뛰기",
      paddingFocus: 10,
      opacityShadow: 0.8,
    ).show(context: context);
  }

  @override
  void dispose() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.removeListener(_onGuideRequested);
    super.dispose();
  }

  @override
  void didUpdateWidget(DailyLogListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateStr != widget.dateStr) {
      _currentDateStr = widget.dateStr;
      _currentDateTitle = widget.dateTitle;
      _loadData();
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
      Navigator.pop(context, _currentDateStr);
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final rawLogs = await DriveLogDatabase.instance.getLogsForWorkDate(_currentDateStr);
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
      showDbrosSnackBar(context, "상세 목록을 불러오는 중 오류가 발생했습니다.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Removed duplicate guide trigger
        });
      }
    }
  }

  Future<void> _openAddLogForm() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DriveLogForm(initialDate: widget.dateStr),
      ),
    );
    if (!mounted) return;
    await _loadData();
    widget.onLogsChanged?.call();
  }

  Future<void> _shareDetailAsImage() async {
    if (!mounted || _isLoading) return;
    if (kIsWeb) {
      showDbrosSnackBar(context, '웹에서는 공유를 지원하지 않습니다.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;

      final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
      final captureWidth = MediaQuery.sizeOf(context).width;
      final lay = _DailyDetailShareLayout.fromWidth(captureWidth);
      final theme = Theme.of(context);

      final captureRoot = Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: MediaQuery(
          data: MediaQuery.of(context),
          child: Theme(
            data: theme,
            child: SizedBox(
              width: captureWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDailyDetailDateHeaderForCapture(theme, captureWidth),
                  for (final log in _dailyLogs)
                    _buildLogTileContent(log, lay, memoMaxLines: 24),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: lay.footerHorizontalPadding,
                      vertical: lay.footerVerticalPadding + 4,
                    ),
                    color: Theme.of(context).cardTheme.color!,
                    child: _buildDailySummaryFooterRow(
                      lay,
                      theme,
                      totalCount: _totalCount,
                      incomeSum: _totalIncomeSum,
                      netSum: _totalNetProfitSum,
                      expenseSum: _totalExpenseSum,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final bytes = await _shareScreenshotController.captureFromLongWidget(
        captureRoot,
        context: context,
        delay: const Duration(milliseconds: 900),
        pixelRatio: pixelRatio,
        constraints: BoxConstraints(
          maxWidth: captureWidth,
          maxHeight: double.maxFinite,
        ),
      );

      if (!mounted) return;
      if (bytes.isEmpty) {
        showDbrosSnackBar(context, '이미지를 만들 수 없습니다. 잠시 후 다시 시도해 주세요.');
        return;
      }

      final dir = await getTemporaryDirectory();
      if (!mounted) return;
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
      showDbrosSnackBar(context, '공유에 실패했습니다: $e');
    }
  }

  /// [LogListPage] 의 `_buildMonthHeader` 와 동일 톤의 상단 바 — 근무일자(가운데 정렬).
  Widget _buildDailyDetailDateHeader() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth > 600;
    final compact = widget.embedded; // true=펼친화면(embedded), false=접힌화면(단독)
    final padding = compact ? 6.0 : (isTablet ? 12.0 : 8.0);
    final hPad = compact ? 8.0 : (isTablet ? 12.0 : 8.0);
    final hasCoordinates = _dailyLogs.any((log) => log['start_lat'] != null);
    
    // 가이드 타겟을 위해 지도 버튼 영역은 항상 확보 (좌표가 없으면 비활성화 상태로 표시)
    final leftSlot  = compact ? (kMapFeaturesEnabled ? 36.0 : 0.0) : 0.0;
    final rightSlot = compact ? 96.0 : (kMapFeaturesEnabled ? 36.0 : 0.0);
    
    final titleStyle = (compact ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(fontWeight: FontWeight.bold, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white));
        
    final mapBtn = InkWell(
      key: _keyDailyMapBtn,
      onTap: hasCoordinates ? _openDailyRouteMap : () {
        showDbrosSnackBar(context, '저장된 GPS 좌표가 없어 지도를 표시할 수 없습니다.');
      },
      child: Padding(
        padding: EdgeInsets.all(4.0),
        child: Icon(
          Icons.map, 
          color: hasCoordinates ? Color(0xFF4FC3F7) : Colors.grey.withOpacity(0.5), 
          size: 18
        ),
      ),
    );

    return Container(
      color: Theme.of(context).cardTheme.color!,
      padding: EdgeInsets.symmetric(vertical: padding, horizontal: hPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 좌측 슬롯: 펼친화면에서만 지도버튼 노출
          SizedBox(
            width: leftSlot,
            child: compact && kMapFeaturesEnabled
                ? Align(alignment: Alignment.centerLeft, child: mapBtn)
                : const SizedBox.shrink(),
          ),
          Expanded(
            key: _keyDailyDateNav,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                  onPressed: () => _goToAdjacentDay(false),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                Flexible(
                  child: Text(
                    _currentDateTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                  onPressed: () => _goToAdjacentDay(true),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
          ),
          // 우측 슬롯: 펼친화면=[+입력], 접힌화면=지도버튼(맨 끝)
          SizedBox(
            width: rightSlot,
            child: Align(
              alignment: Alignment.centerRight,
              child: compact
                  ? TextButton.icon(
                      onPressed: _openAddLogForm,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(Icons.add_circle_outline, size: 16, color: Color(0xFFFFC700)),
                      label: Text(
                        '입력',
                        style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    )
                  : (kMapFeaturesEnabled ? mapBtn : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyDetailDateHeaderForCapture(ThemeData theme, double captureWidth) {
    final isTablet = captureWidth > 600;
    final padding = isTablet ? 12.0 : 8.0;
    return Container(
      color: Theme.of(context).cardTheme.color!,
      padding: EdgeInsets.symmetric(vertical: padding),
      alignment: Alignment.center,
      child: Text(
        widget.dateTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
            ),
      ),
    );
  }

  Widget _buildDetailBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDailyDetailDateHeader(),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
              : ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(child: _buildLogsBody()),
                          if (widget.embedded)
                            _buildEmbeddedDailySummaryFooter()
                          else
                            _buildDailySummaryFooter(),
                        ],
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 80, // 대략적인 리스트 상세 아이템 높이
                        child: IgnorePointer(
                          child: Container(key: _keyDailyItem),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLogsBody() {
    if (!_isLoading && _dailyLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '등록된 운행일지가 없습니다',
              style: TextStyle(color: Color(0xFF6E717C), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            if (widget.embedded)
              FilledButton(
                onPressed: _openAddLogForm,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Theme.of(context).scaffoldBackgroundColor,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  '+ 일지 입력',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
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
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _buildDetailBody(),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardTheme.color!,
        leading: IconButton(icon: Icon(Icons.arrow_back_ios, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)), onPressed: () => Navigator.pop(context)),
        title: Text(
          '운행 일지 상세',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
        ),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            TextButton(
              key: _keyDailyShareBtn,
              onPressed: _shareDetailAsImage,
              child: Text(
                '공유',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 15 : 14,
                ),
              ),
            ),
        ],
      ),
      body: ResponsiveBody(
        child: _buildDetailBody(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedItemColor: Theme.of(context).primaryColor, 
          unselectedItemColor: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey), 
          selectedFontSize: 12,
          unselectedFontSize: 12,
          currentIndex: 1, 
          onTap: (index) {
            if (index == 2) {
              _openAddLogForm();
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
          items: [
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

  Widget _buildLogTileContent(
    Map<String, dynamic> log,
    _DailyDetailShareLayout lay, {
    int memoMaxLines = 4,
  }) {
    final String time = log['drive_time'].toString().replaceFirst(':', '시 ') + "분";
    final fullStart = log['start_location']?.toString().trim();
    final fullEnd = log['end_location']?.toString().trim();
    final fullWp = log['waypoint']?.toString().trim();
    final locStyle = TextStyle(color: Theme.of(context).primaryColor, fontSize: lay.locationFontSize);
    final arrowIcon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.arrow_forward, color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey), size: lay.isTablet ? 14 : 12),
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
    final g = _toInt(log['gross_fare']);
    final tip = _toInt(log['waypoint_tip']);
    final revenue = g + tip;

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5))),
      padding: EdgeInsets.symmetric(horizontal: lay.rowHorizontalPadding, vertical: lay.rowVerticalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text('[ $time ]', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold, fontSize: lay.timeFontSize)),
                    SizedBox(width: lay.innerSpacing),
                    Expanded(
                      child: Text(
                        log['program']?.toString() ?? '',
                        style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7), fontSize: lay.programFontSize),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: lay.innerSpacing),
                    DriveLogSourceChip(registrationSource: log['registration_source']?.toString()),
                  ],
                ),
              ),
              SizedBox(width: lay.innerSpacing),
              SizedBox(width: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '수입 : ', 
                      style: TextStyle(
                        color: revenue == 0 ? const Color(0xFFFF5252) : Colors.lightBlueAccent, 
                        fontSize: 13
                      )
                    ),
                    TextSpan(
                      text: revenue == 0 ? '⚠️ 미입력' : '₩${NumberFormat('#,###').format(revenue)}',
                      style: TextStyle(
                        color: revenue == 0 ? const Color(0xFFFF5252) : Colors.lightBlueAccent, 
                        fontSize: lay.incomeFontSize, 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
          SizedBox(height: lay.rowSpacing),
          Row(
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
          ),
          SizedBox(height: lay.rowSpacing / 2),
          if ((log['memo'] ?? '').toString().trim().isNotEmpty)
            Text(
              (log['memo'] ?? '').toString().trim(),
              style: TextStyle(
                color: const Color(0xFF39FF14),
                fontSize: lay.locationFontSize - 1,
                fontWeight: FontWeight.w600,
              ),
              maxLines: memoMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildDailySummaryFooterRow(
    _DailyDetailShareLayout lay,
    ThemeData theme, {
    required int totalCount,
    required int incomeSum,
    required int netSum,
    required int expenseSum,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                "[ 일일 합계 ]",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("$totalCount건", style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: lay.footerInfoFontSize)),
                    SizedBox(width: 12),
                    Text("수입 : ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                    Text(
                      "₩${NumberFormat('#,###').format(incomeSum)}",
                      style: TextStyle(color: Colors.lightBlueAccent, fontSize: lay.footerInfoFontSize, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: lay.footerSpacing),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: "순익 : ", style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                      TextSpan(text: "₩${NumberFormat('#,###').format(netSum)}", style: TextStyle(color: Color(0xFFFFC700), fontSize: lay.footerInfoFontSize)),
                    ],
                  ),
                ),
              ),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: "지출 : ", style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      TextSpan(text: "-₩${NumberFormat('#,###').format(expenseSum)}", style: TextStyle(color: const Color(0xFFFF5252), fontSize: lay.footerInfoFontSize)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      itemCount: _dailyLogs.length,
      itemBuilder: (context, index) {
        final log = _dailyLogs[index];
        final String time = log['drive_time'].toString().replaceFirst(':', '시 ') + "분";
        final lay = _DailyDetailShareLayout.fromWidth(MediaQuery.sizeOf(context).width);

        return Container(
          child: Dismissible(
            key: Key(log['id'].toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: lay.rowHorizontalPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: lay.isTablet ? 26 : 24),
                  SizedBox(height: 4),
                  Text("삭제", style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: lay.isTablet ? 13 : 12)),
                ],
              ),
            ),
            confirmDismiss: (direction) async {
              return await AppGlassDialog.show<bool>(
                context: context,
                dialog: AppGlassDialog(
                  icon: Icons.delete_outline,
                  title: '운행일지 삭제',
                  content: '이 운행일지를 삭제하시겠습니까?\n\n$time ${log['program']}',
                  actions: [
                    Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx, false))),
                    Builder(builder: (ctx) => GlassDialogDestructiveButton(onPressed: () => Navigator.pop(ctx, true))),
                  ],
                ),
              );
            },
            onDismissed: (direction) async {
              await DriveLogDatabase.instance.deleteLog(log['id']);
              _loadData();
              widget.onLogsChanged?.call();

              if (!mounted) return;
              showDbrosSnackBar(
                context,
                "운행일지가 삭제되었습니다.",
                backgroundColor: Colors.red,
              );
            },
            child: InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => DriveLogForm(existingLog: log))).then((_) {
                  _loadData();
                  widget.onLogsChanged?.call();
                });
              },
              child: _buildLogTileContent(log, lay),
            ),
          ),
        );
      }
    );
  }

  /// 펼침 마스터-디테일 우측: 월간 합계와 동일 톤의 하단 고정 일일 합계.
  Widget _buildEmbeddedDailySummaryFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color!,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '[ 일일 합계 ]',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$_totalCount건', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                      SizedBox(width: 10),
                      Text('수입 : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                      Text(
                        '₩${NumberFormat('#,###').format(_totalIncomeSum)}',
                        style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '순익 : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                        TextSpan(text: '₩${NumberFormat('#,###').format(_totalNetProfitSum)}', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '지출 : ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                        TextSpan(text: '-₩${NumberFormat('#,###').format(_totalExpenseSum)}', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailySummaryFooter() {
    final lay = _DailyDetailShareLayout.fromWidth(MediaQuery.sizeOf(context).width);
    return Container(
      padding: EdgeInsets.symmetric(vertical: lay.footerVerticalPadding, horizontal: lay.footerHorizontalPadding),
      color: Theme.of(context).cardTheme.color!,
      child: SafeArea(
        top: false,
        child: _buildDailySummaryFooterRow(
          lay,
          Theme.of(context),
          totalCount: _totalCount,
          incomeSum: _totalIncomeSum,
          netSum: _totalNetProfitSum,
          expenseSum: _totalExpenseSum,
        ),
      ),
    );
  }

  void _openDailyRouteMap() {
    if (!kMapFeaturesEnabled) return;

    final segments = <TripSegment>[];
    for (final log in _dailyLogs) {
      final startLat = (log['start_lat'] as num?)?.toDouble();
      final startLng = (log['start_lng'] as num?)?.toDouble();
      final endLat = (log['end_lat'] as num?)?.toDouble();
      final endLng = (log['end_lng'] as num?)?.toDouble();

      final startLoc = (log['start_location'] ?? '').toString();
      final endLoc = (log['end_location'] ?? '').toString();

      if (startLat != null && startLng != null && endLat != null && endLng != null) {
        final time = log['drive_time']?.toString() ?? '';
        final prog = log['program']?.toString() ?? '';
        
        segments.add(
          TripSegment(
            start: LatLng(startLat, startLng),
            end: LatLng(endLat, endLng),
            startSnippet: '$prog · $time\n(${startLoc.isNotEmpty ? startLoc : '주소 정보 없음'})',
            endSnippet: '$prog · $time\n(${endLoc.isNotEmpty ? endLoc : '주소 정보 없음'})',
          ),
        );
      }
    }

    if (segments.isEmpty) {
      if (!mounted) return;
      showDbrosSnackBar(context, '해당 날짜에 기록된 좌표가 없습니다.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatsRouteMapPage(
          periodLabel: '일간',
          dateLabel: _currentDateTitle,
          segments: segments,
        ),
      ),
    );
  }

  Future<void> _goToAdjacentDay(bool isNext) async {
    final db = await DriveLogDatabase.instance.database;
    final operator = isNext ? '>' : '<';
    final order = isNext ? 'ASC' : 'DESC';
    final res = await db.query(
      'drive_logs',
      columns: ['drive_date'],
      where: 'drive_date $operator ?',
      whereArgs: [_currentDateStr],
      orderBy: 'drive_date $order',
      limit: 1,
    );

    if (res.isNotEmpty) {
      final newDate = res.first['drive_date'] as String;
      if (widget.embedded && widget.onDateChanged != null) {
        widget.onDateChanged!(newDate);
      } else {
        setState(() {
          _currentDateStr = newDate;
          _currentDateTitle = newDate;
          _isLoading = true;
        });
        _loadData();
      }
    } else {
      if (!mounted) return;
      showDbrosSnackBar(context, isNext ? '다음 근무일지가 없습니다.' : '이전 근무일지가 없습니다.');
    }
  }
}

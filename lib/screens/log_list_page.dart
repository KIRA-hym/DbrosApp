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

/// Î™©Î°ù¬∑?ÅÏÑ∏ Í≥µÌÜµ: ?òÏûÖ=?îÍ∏à+Í≤ΩÏú†?? ÏßÄÏ∂??òÏàòÎ£?ÍµêÌÜµÎπ? ?úÏùµ=?îÍ∏à-?òÏàòÎ£?ÍµêÌÜµÎπ?Í≤ΩÏú†??
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
  String _currentSort = 'date_asc';

  bool _isSearchActive = false;
  String _searchQuery = '';
  final TextEditingController _searchCon = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

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
  /// ÎßàÏä§???îÌÖå???∞Ï∏° ?®ÎÑê Í∞ïÏ†ú Í∞±Ïã†(?òÎ£® ??†ú¬∑???∞Ïù¥??reload ??.
  int _detailRevision = 0;
  bool? _wasExpanded;

  /// ?ºÏπ® ÎßàÏä§???îÌÖå??Í∏∞Î≥∏ ?†ÌÉù: Î≥¥Îäî ?¨Ïóê **?§Îäò Í∑ºÎ¨¥??*???àÏúºÎ©?Í∑??†Ïßú, ?ÜÏúºÎ©?null(?∞Ï∏° Îπ??®ÎÑê).
  String? _initialMasterDetailDateInFocusedMonth() {
    final workYmd = WorkDateUtils.effectiveWorkDateYmd();
    final parsed = DateTime.tryParse(workYmd);
    if (parsed == null) return null;
    if (parsed.year == _focusedMonth.year && parsed.month == _focusedMonth.month) {
      return workYmd;
    }
    return null;
  }

  Map<String, List<Map<String, dynamic>>> get _filteredGroupedLogs {
    if (!_isSearchActive || _searchQuery.isEmpty) return _groupedLogs;
    final query = _searchQuery.toLowerCase();
    
    final filtered = <String, List<Map<String, dynamic>>>{};
    for (final entry in _groupedLogs.entries) {
      final matchingLogs = entry.value.where((log) {
        final startLoc = (log['start_location']?.toString() ?? '').toLowerCase();
        final endLoc = (log['end_location']?.toString() ?? '').toLowerCase();
        final waypoint = (log['waypoint']?.toString() ?? '').toLowerCase();
        final program = (log['program']?.toString() ?? '').toLowerCase();
        final memo = (log['memo']?.toString() ?? '').toLowerCase();
        return startLoc.contains(query) || endLoc.contains(query) || waypoint.contains(query) || program.contains(query) || memo.contains(query);
      }).toList();
      if (matchingLogs.isNotEmpty) {
        filtered[entry.key] = matchingLogs;
      }
    }
    return filtered;
  }

  int get _filteredTotalCount {
    if (!_isSearchActive || _searchQuery.isEmpty) return _filteredTotalCount;
    return _filteredGroupedLogs.values.fold(0, (sum, logs) => sum + logs.length);
  }

  int get _filteredTotalGross {
    if (!_isSearchActive || _searchQuery.isEmpty) return _totalGross;
    return _filteredGroupedLogs.values.expand((l) => l).fold(0, (sum, log) => sum + _rowIncomePlusTip(log));
  }

  int get _filteredTotalNet {
    if (!_isSearchActive || _searchQuery.isEmpty) return _totalNet;
    return _filteredGroupedLogs.values.expand((l) => l).fold(0, (sum, log) => sum + _rowNetProfit(log));
  }

  int get _filteredTotalExpenses {
    if (!_isSearchActive || _searchQuery.isEmpty) return _totalExpenses;
    return _filteredGroupedLogs.values.expand((l) => l).fold(0, (sum, log) => sum + _rowExpenseFeePlusTransport(log));
  }

  Widget _buildSearchFilters() {
    final List<String> programs = ['?¨Ïñ¥', 'Í≥®ÌîÑ', '?ºÎ∞ò', '?®Îî©', 'VIP'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: programs.map((p) {
            final isSelected = _searchQuery == p;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(p),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _searchQuery = p;
                      _searchCon.text = p;
                    } else {
                      _searchQuery = '';
                      _searchCon.clear();
                    }
                  });
                },
                selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                checkmarkColor: Theme.of(context).primaryColor,
              ),
            );
          }).toList(),
        ),
      ),
    );
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
                        Text('$logCountÍ±?, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                        TextSpan(
                          text: '??{NumberFormat('#,###').format(dailyIncome)}',
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
                      label: '?úÏùµ',
                      amount: dailyNetProfit,
                      labelColor: Theme.of(context).primaryColor,
                      valueColor: Theme.of(context).primaryColor,
                      prefix: '??,
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: _buildMasterDetailAmountRow(
                      label: 'ÏßÄÏ∂?,
                      amount: dailyExpense,
                      labelColor: const Color(0xFFFF5252),
                      valueColor: const Color(0xFFFF5252),
                      prefix: '-??,
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
                  '[ ?îÍ∞Ñ ?©Í≥Ñ ]',
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
                      Text('$_filteredTotalCountÍ±?, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                      SizedBox(width: 10),
                      Text('?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                      Text(
                        '??{NumberFormat('#,###').format(_filteredTotalGross)}',
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
                        const TextSpan(text: '?úÏùµ : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                        TextSpan(text: '??{NumberFormat('#,###').format(_filteredTotalNet)}', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
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
                        const TextSpan(text: 'ÏßÄÏ∂?: ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                        TextSpan(text: '-??{NumberFormat('#,###').format(_filteredTotalExpenses)}', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
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
                title: "?îÍ∞Ñ ?ºÏ? ?¥Îèô",
                description: "Ï¢åÏö∞ ?îÏÇ¥?úÎ? ?åÎü¨ ?¥Ï†Ñ/?§Ïùå ?¨Ïùò ?¥Ìñâ Í∏∞Î°ù???ïÏù∏?????àÏñ¥??",
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
                title: "?îÍ∞Ñ Í∏∞Î°ù Í≥µÏú†",
                description: "?ÑÏû¨ Î≥¥Í≥† ?àÎäî ?îÍ∞Ñ ?¥Ìñâ ?¥Ïó≠ ?ÑÏ≤¥Î•??¥Î?ÏßÄÎ°?Ï∫°Ï≤ò?¥ÏÑú Ïπ¥Ïπ¥?§ÌÜ° ?±ÏúºÎ°?Í≥µÏú†?????àÏñ¥??",
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
                title: "?ÅÏÑ∏ ÏßÑÏûÖ Î∞??§Ï??¥ÌîÑ ??†ú",
                description: "?†ÏßúÎ•??∞Ïπò?òÎ©¥ ?¥Îãπ ?ºÏûê???ÅÏÑ∏ ?¥Ïó≠??Î≥????àÍ≥†, ??™©???ºÏ™Ω?ºÎ°ú ?§Ï??¥ÌîÑ?òÎ©¥ Í∑??†Ïùò Í∏∞Î°ù??Î™®Îëê ??†ú?????àÏñ¥??",
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
                title: "?îÍ∞Ñ ?òÏûÖ/ÏßÄÏ∂??îÏïΩ",
                description: "?????ôÏïà??Ï¥??¥Ìñâ Í±¥Ïàò?Ä ?òÏûÖ, ÏßÄÏ∂? ?úÏàò?µÏùÑ ?úÎàà???åÏïÖ?òÏÑ∏??",
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
      textSkip: "Í±¥ÎÑà?∞Í∏∞",
      paddingFocus: 10,
      opacityShadow: 0.8,
    ).show(context: context);
  }

  @override
  void dispose() {
    _searchCon.dispose();
    _searchFocus.dispose();
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
      _filteredTotalCount = count;
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
        leading: IconButton(
          icon: Icon(_isSearchActive ? Icons.arrow_back : Icons.search, color: Theme.of(context).primaryColor),
          onPressed: () {
            setState(() {
              _isSearchActive = !_isSearchActive;
              if (!_isSearchActive) {
                _searchQuery = '';
                _searchCon.clear();
              }
            });
            if (_isSearchActive) {
              _searchFocus.requestFocus();
            }
          },
        ),
        title: _isSearchActive
            ? TextField(
                controller: _searchCon,
                focusNode: _searchFocus,
                decoration: const InputDecoration(
                  hintText: 'Í≤Ä??(Ï∂úÎ∞ú, ?ÑÏ∞©, ?ÑÎ°úÍ∑∏Îû® ??',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: Theme.of(context).primaryColor),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              )
            : Text(
                "?¥Ìñâ ?ºÏ? Î™©Î°ù",
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
                'Í≥µÏú†',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: ResponsiveLayout.isFoldOrTablet(context) ? 15 : 14,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearchActive) _buildSearchFilters(),
          Expanded(
            child: (_isSearchActive && _searchQuery.isNotEmpty)
                ? DailyLogListPage(
                    dateStr: '',
                    dateTitle: 'Í≤Ä??Í≤∞Í≥º',
                    embedded: isExpanded,
                    isSearchMode: true,
                    searchResults: _filteredGroupedLogs.values.expand((e) => e).toList(),
                    onLogsChanged: _loadMonthData,
                  )
                : (isExpanded
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
                      )),
          ),
        ],
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
                                      height: 70, // ?Ä?µÏ†Å??Î¶¨Ïä§???ÑÏù¥???íÏù¥
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
                                '?ºÏ™Ω?êÏÑú ?†ÏßúÎ•??†ÌÉù?òÏÑ∏??,
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
            DateFormat('yyyy??MM??).format(_focusedMonth), 
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
            startSnippet: '$program ¬∑ $time\n(${startLoc.isNotEmpty ? startLoc : 'Ï£ºÏÜå ?ïÎ≥¥ ?ÜÏùå'})',
            endSnippet: '$program ¬∑ $time\n(${endLoc.isNotEmpty ? endLoc : 'Ï£ºÏÜå ?ïÎ≥¥ ?ÜÏùå'})',
          ),
        );
      }
    }

    if (segments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('?¥Îãπ ?ºÏûê???úÏãú??Ï¢åÌëú ?∞Ïù¥?∞Í? ?ÜÏäµ?àÎã§.')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatsRouteMapPage(
          periodLabel: '?ºÍ∞Ñ',
          dateLabel: 'Í∑ºÎ¨¥?ºÏûê: $dateStr',
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
                trailing: Text("<?ºÏ? ?ÖÎ†•>", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
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
                    Text("??†ú", style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: isTablet ? 13 : 12)),
                  ],
                ),
              ),
              confirmDismiss: (direction) async {
                return await AppGlassDialog.show<bool>(
                  context: context,
                  dialog: AppGlassDialog(
                    icon: Icons.delete_outline,
                    title: '?òÎ£® ?ºÏ? ??†ú',
                    content: '$dateStr???¥Ìñâ?ºÏ? $logCountÍ±¥ÏùÑ Î™®Îëê ??†ú?òÏãúÍ≤†Ïäµ?àÍπå?',
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
                  "$dateStr??Î™®Îì† ?¥Ìñâ?ºÏ?Í∞Ä ??†ú?òÏóà?µÎãà??",
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
                                            Text('$logCountÍ±?, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(text: '?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                                            TextSpan(
                                              text: '??{NumberFormat('#,###').format(dailyIncome)}',
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
                                          label: '?úÏùµ',
                                          amount: dailyNetProfit,
                                          labelColor: Theme.of(context).primaryColor,
                                          valueColor: Theme.of(context).primaryColor,
                                          prefix: '??,
                                        ),
                                      ),
                                      SizedBox(width: spacing),
                                      Expanded(
                                        child: _buildMasterDetailAmountRow(
                                          label: 'ÏßÄÏ∂?,
                                          amount: dailyExpense,
                                          labelColor: const Color(0xFFFF5252),
                                          valueColor: const Color(0xFFFF5252),
                                          prefix: '-??,
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
                    '[ ?îÍ∞Ñ ?©Í≥Ñ ]',
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
                        Text('$_filteredTotalCountÍ±?, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: infoFontSize)),
                        SizedBox(width: 12),
                        Text('?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                        Text(
                          '??{NumberFormat('#,###').format(_filteredTotalGross)}',
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
                          const TextSpan(text: '?úÏùµ : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                          TextSpan(text: '??{NumberFormat('#,###').format(_filteredTotalNet)}', style: TextStyle(color: Color(0xFFFFC700), fontSize: infoFontSize)),
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
                          const TextSpan(text: 'ÏßÄÏ∂?: ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                          TextSpan(text: '-??{NumberFormat('#,###').format(_filteredTotalExpenses)}', style: TextStyle(color: const Color(0xFFFF5252), fontSize: infoFontSize)),
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
      showDbrosSnackBar(context, '?∞ÏùÑ ?ëÏ? ?ÅÌÉú?êÏÑúÎß?Í≥µÏú† Í∏∞Îä•??Í∞Ä?•Ìï©?àÎã§.');
      return;
    }
    if (kIsWeb) {
      showDbrosSnackBar(context, '?πÏóê?úÎäî Í≥µÏú†Î•?ÏßÄ?êÌïòÏßÄ ?äÏäµ?àÎã§.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
      final captureWidth = MediaQuery.sizeOf(context).width;
      final theme = Theme.of(context);
      final ymTitle = DateFormat('yyyy??MM??).format(_focusedMonth);
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
                    '?¥Ìñâ ?ºÏ? Î™©Î°ù  $ymTitle',
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
        showDbrosSnackBar(context, '?¥Î?ÏßÄÎ•?ÎßåÎì§ ???ÜÏäµ?àÎã§. ?†Ïãú ???§Ïãú ?úÎèÑ??Ï£ºÏÑ∏??');
        return;
      }

      final dir = await getTemporaryDirectory();
      if (!mounted) return;
      final safe = DateFormat('yyyyMM').format(_focusedMonth);
      final file = File(p.join(dir.path, 'dbros_monthly_$safe.png'));
      await file.writeAsBytes(bytes, flush: true);

      final title = '?¥Ìñâ ?ºÏ? Î™©Î°ù $ymTitle';
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
      showDbrosSnackBar(context, 'Í≥µÏú†???§Ìå®?àÏäµ?àÎã§: $e');
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
              Text('<?ºÏ? ?ÖÎ†•>', style: theme.textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
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
                  Text('$logCountÍ±?, style: theme.textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white))),
                  SizedBox(height: innerSpacing),
                  Row(
                    children: [
                      Text(
                        '?úÏùµ : ??{NumberFormat('#,###').format(dailyNetProfit)}',
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
                    Text('?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                    Text(
                      '??{NumberFormat('#,###').format(dailyIncome)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.lightBlueAccent),
                    ),
                  ],
                ),
                SizedBox(height: innerSpacing),
                Row(
                  children: [
                    Text('ÏßÄÏ∂?: ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                    Text(
                      '-??{NumberFormat('#,###').format(dailyExpense)}',
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
                  '[ ?îÍ∞Ñ ?©Í≥Ñ ]',
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
                      Text('$_filteredTotalCountÍ±?, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: infoFontSize)),
                      SizedBox(width: 12),
                      Text('?úÏùµ : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 14)),
                      Text(
                        '??{NumberFormat('#,###').format(_filteredTotalNet)}',
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
                        const TextSpan(text: '?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                        TextSpan(text: '??{NumberFormat('#,###').format(_filteredTotalGross)}', style: TextStyle(color: Colors.lightBlueAccent, fontSize: infoFontSize)),
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
                        const TextSpan(text: 'ÏßÄÏ∂?: ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                        TextSpan(text: '-??{NumberFormat('#,###').format(_filteredTotalExpenses)}', style: TextStyle(color: const Color(0xFFFF5252), fontSize: infoFontSize)),
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
  /// ?Ä??ÏßÅÌõÑ ???îÎ©¥?êÏÑú ?§ÎÇµ???ÑÏö∏ ??(?ëÏÑ± ?îÎ©¥?êÏÑú ?Ä???§ÎÇµ ??pop ?òÎ©¥ Îß§Îãà?Ä/?§Î≤Ñ?àÏù¥Í∞Ä Íº¨Ïùº ???àÏùå)
  final String? snackMessage;

  const DailyLogListPage({
    super.key,
    required this.dateStr,
    required this.dateTitle,
    this.snackMessage,
    this.embedded = false,
    this.onLogsChanged,
    this.onDateChanged,
    this.isSearchMode = false,
    this.searchResults,
  });

  /// Î™©Î°ù ÎßàÏä§???îÌÖå???§Î•∏Ï™??®ÎÑê??
  final bool embedded;
  final VoidCallback? onLogsChanged;
  final ValueChanged<String>? onDateChanged;
  
  final bool isSearchMode;
  final List<Map<String, dynamic>>? searchResults;

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
                title: "?§Î•∏ ?†Ïßú Î≥¥Í∏∞",
                description: "?ÅÎã®???îÏÇ¥?úÎ? ?åÎü¨ ?¥Ï†Ñ ?†Ïßú???§Ïùå ?†Ïßú???¥Ìñâ ?ºÏ?Î°?Î∞îÎ°ú ?¥Îèô?????àÏñ¥??",
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
                  title: "?ºÏùº ?ôÏÑ† Îß?,
                  description: "ÏßÄ???ÑÏù¥ÏΩòÏùÑ ?ÑÎ•¥Î©?Í∑∏ÎÇ† ?òÎ£® ?ôÏïà ?¥Îèô???ÑÏ≤¥ Í≤ΩÎ°úÎ•?ÏßÄ?ÑÏóê???úÎàà??Î≥????àÏñ¥?? (GPS ?∞Ïù¥?∞Í? ?ÜÏúºÎ©?ÎπÑÌôú?±Ìôî?©Îãà??",
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
                title: "?ºÏ? ?òÏ†ï Î∞???†ú",
                description: "Í∞úÎ≥Ñ ??™©???∞Ïπò???òÏ†ï?òÍ±∞?? ?ºÏ™Ω?ºÎ°ú ?§Ï??¥ÌîÑ?¥ÏÑú Î∂àÌïÑ?îÌïú ?ºÏ?Î•?Í∞úÎ≥Ñ ??†ú?????àÏñ¥??",
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
                title: "?òÎ£® Í∏∞Î°ù Í≥µÏú†",
                description: "?òÎ£® ?ôÏïà???¥Ìñâ ?¥Ïó≠Í≥??òÏûÖ/ÏßÄÏ∂??©Í≥ÑÎ•?Ï∫°Ï≤ò?òÏó¨ ?§Î•∏ ?¨Îûå?êÍ≤å Í≥µÏú†?????àÏñ¥??",
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
      textSkip: "Í±¥ÎÑà?∞Í∏∞",
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
    if (oldWidget.dateStr != widget.dateStr || (widget.isSearchMode && oldWidget.searchResults != widget.searchResults)) {
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
      List<Map<String, dynamic>> logs;
      if (widget.isSearchMode && widget.searchResults != null) {
        logs = widget.searchResults!;
      } else {
        final rawLogs = await DriveLogDatabase.instance.getLogsForWorkDate(_currentDateStr);
        logs = List<Map<String, dynamic>>.from(rawLogs);
      }
      
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
      showDbrosSnackBar(context, "?ÅÏÑ∏ Î™©Î°ù??Î∂àÎü¨?§Îäî Ï§??§Î•òÍ∞Ä Î∞úÏÉù?àÏäµ?àÎã§.");
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
      showDbrosSnackBar(context, '?πÏóê?úÎäî Í≥µÏú†Î•?ÏßÄ?êÌïòÏßÄ ?äÏäµ?àÎã§.');
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
                      totalCount: _filteredTotalCount,
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
        showDbrosSnackBar(context, '?¥Î?ÏßÄÎ•?ÎßåÎì§ ???ÜÏäµ?àÎã§. ?†Ïãú ???§Ïãú ?úÎèÑ??Ï£ºÏÑ∏??');
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
      showDbrosSnackBar(context, 'Í≥µÏú†???§Ìå®?àÏäµ?àÎã§: $e');
    }
  }

  /// [LogListPage] ??`_buildMonthHeader` ?Ä ?ôÏùº ?§Ïùò ?ÅÎã® Î∞???Í∑ºÎ¨¥?ºÏûê(Í∞Ä?¥Îç∞ ?ïÎ†¨).
  Widget _buildDailyDetailDateHeader() {
    if (widget.isSearchMode) return const SizedBox.shrink();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTablet = screenWidth > 600;
    final compact = widget.embedded; // true=?ºÏπú?îÎ©¥(embedded), false=?ëÌûå?îÎ©¥(?®ÎèÖ)
    final padding = compact ? 6.0 : (isTablet ? 12.0 : 8.0);
    final hPad = compact ? 8.0 : (isTablet ? 12.0 : 8.0);
    final hasCoordinates = _dailyLogs.any((log) => log['start_lat'] != null);
    
    // Í∞Ä?¥Îìú ?ÄÍ≤üÏùÑ ?ÑÌï¥ ÏßÄ??Î≤ÑÌäº ?ÅÏó≠?Ä ??ÉÅ ?ïÎ≥¥ (Ï¢åÌëúÍ∞Ä ?ÜÏúºÎ©?ÎπÑÌôú?±Ìôî ?ÅÌÉúÎ°??úÏãú)
    final leftSlot  = compact ? (kMapFeaturesEnabled ? 36.0 : 0.0) : 0.0;
    final rightSlot = compact ? 96.0 : (kMapFeaturesEnabled ? 36.0 : 0.0);
    
    final titleStyle = (compact ? Theme.of(context).textTheme.titleSmall : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(fontWeight: FontWeight.bold, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white));
        
    final mapBtn = InkWell(
      key: _keyDailyMapBtn,
      onTap: hasCoordinates ? _openDailyRouteMap : () {
        showDbrosSnackBar(context, '?Ä?•Îêú GPS Ï¢åÌëúÍ∞Ä ?ÜÏñ¥ ÏßÄ?ÑÎ? ?úÏãú?????ÜÏäµ?àÎã§.');
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
          // Ï¢åÏ∏° ?¨Î°Ø: ?ºÏπú?îÎ©¥?êÏÑúÎß?ÏßÄ?ÑÎ≤Ñ???∏Ï∂ú
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
          // ?∞Ï∏° ?¨Î°Ø: ?ºÏπú?îÎ©¥=[+?ÖÎ†•], ?ëÌûå?îÎ©¥=ÏßÄ?ÑÎ≤Ñ??Îß???
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
                        '?ÖÎ†•',
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
                        height: 80, // ?Ä?µÏ†Å??Î¶¨Ïä§???ÅÏÑ∏ ?ÑÏù¥???íÏù¥
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
              '?±Î°ù???¥Ìñâ?ºÏ?Í∞Ä ?ÜÏäµ?àÎã§',
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
                  '+ ?ºÏ? ?ÖÎ†•',
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
          '?¥Ìñâ ?ºÏ? ?ÅÏÑ∏',
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
                'Í≥µÏú†',
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
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), activeIcon: Icon(Icons.home), label: "??),
            BottomNavigationBarItem(icon: Icon(Icons.list_alt), activeIcon: Icon(Icons.list_alt), label: "Î™©Î°ù"),
            BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: "?ëÏÑ±"),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), activeIcon: Icon(Icons.bar_chart), label: "?µÍ≥Ñ"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: "?§Ï†ï"),
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
    final String time = log['drive_time'].toString().replaceFirst(':', '??') + "Î∂?;
    final fullStart = log['start_location']?.toString().trim();
    final fullEnd = log['end_location']?.toString().trim();
    final fullWp = log['waypoint']?.toString().trim();
    final locStyle = TextStyle(color: Theme.of(context).primaryColor, fontSize: lay.locationFontSize);
    final arrowIcon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.arrow_forward, color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey), size: lay.isTablet ? 14 : 12),
    );

    final hasStartLoc = fullStart != null && fullStart.isNotEmpty;
    final hasStartCoord = log['start_lat'] != null && log['start_lng'] != null;
    
    final hasEndLoc = fullEnd != null && fullEnd.isNotEmpty;
    final hasEndCoord = log['end_lat'] != null && log['end_lng'] != null;

    Widget segment(String? full, String placeholder, {TextAlign align = TextAlign.start, bool hasCoordinate = true, bool isMissing = false}) {
      final t = (full != null && full.isNotEmpty) ? full : placeholder;
      final displayWidget = Text(
        isMissing ? '?†Ô∏è ?ÑÎùΩ' : t,
        style: locStyle.copyWith(color: isMissing ? const Color(0xFFFF5252) : null),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
      );

      if (!hasCoordinate && !isMissing && full != null && full.isNotEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: align == TextAlign.end ? MainAxisAlignment.end : (align == TextAlign.center ? MainAxisAlignment.center : MainAxisAlignment.start),
          children: [
            if (align != TextAlign.end) const Icon(Icons.location_off, color: Colors.orange, size: 14),
            if (align != TextAlign.end) const SizedBox(width: 4),
            Flexible(child: displayWidget),
            if (align == TextAlign.end) const SizedBox(width: 4),
            if (align == TextAlign.end) const Icon(Icons.location_off, color: Colors.orange, size: 14),
          ],
        );
      }
      return displayWidget;
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
                      text: '?òÏûÖ : ', 
                      style: TextStyle(
                        color: revenue == 0 ? const Color(0xFFFF5252) : Colors.lightBlueAccent, 
                        fontSize: 13
                      )
                    ),
                    TextSpan(
                      text: revenue == 0 ? '?†Ô∏è ÎØ∏ÏûÖ?? : '??{NumberFormat('#,###').format(revenue)}',
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
              Expanded(flex: 1, child: segment(fullStart, 'Ï∂úÎ∞úÏßÄ', isMissing: !hasStartLoc, hasCoordinate: hasStartCoord)),
              arrowIcon,
              if (hasWp) ...[
                Expanded(flex: 1, child: segment(fullWp, 'Í≤ΩÏú†', align: TextAlign.center)),
                arrowIcon,
              ],
              Expanded(flex: 1, child: segment(fullEnd, '?ÑÏ∞©ÏßÄ', align: TextAlign.end, isMissing: !hasEndLoc, hasCoordinate: hasEndCoord)),
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
                "[ ?ºÏùº ?©Í≥Ñ ]",
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
                    Text("$totalCountÍ±?, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: lay.footerInfoFontSize)),
                    SizedBox(width: 12),
                    Text("?òÏûÖ : ", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                    Text(
                      "??{NumberFormat('#,###').format(incomeSum)}",
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
                      const TextSpan(text: "?úÏùµ : ", style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                      TextSpan(text: "??{NumberFormat('#,###').format(netSum)}", style: TextStyle(color: Color(0xFFFFC700), fontSize: lay.footerInfoFontSize)),
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
                      const TextSpan(text: "ÏßÄÏ∂?: ", style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                      TextSpan(text: "-??{NumberFormat('#,###').format(expenseSum)}", style: TextStyle(color: const Color(0xFFFF5252), fontSize: lay.footerInfoFontSize)),
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
        final String time = log['drive_time'].toString().replaceFirst(':', '??') + "Î∂?;
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
                  Text("??†ú", style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: lay.isTablet ? 13 : 12)),
                ],
              ),
            ),
            confirmDismiss: (direction) async {
              return await AppGlassDialog.show<bool>(
                context: context,
                dialog: AppGlassDialog(
                  icon: Icons.delete_outline,
                  title: '?¥Ìñâ?ºÏ? ??†ú',
                  content: '???¥Ìñâ?ºÏ?Î•???†ú?òÏãúÍ≤†Ïäµ?àÍπå?\n\n$time ${log['program']}',
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
                "?¥Ìñâ?ºÏ?Í∞Ä ??†ú?òÏóà?µÎãà??",
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

  /// ?ºÏπ® ÎßàÏä§???îÌÖå???∞Ï∏°: ?îÍ∞Ñ ?©Í≥Ñ?Ä ?ôÏùº ?§Ïùò ?òÎã® Í≥†Ï†ï ?ºÏùº ?©Í≥Ñ.
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
                  '[ ?ºÏùº ?©Í≥Ñ ]',
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
                      Text('$_filteredTotalCountÍ±?, style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 13)),
                      SizedBox(width: 10),
                      Text('?òÏûÖ : ', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13)),
                      Text(
                        '??{NumberFormat('#,###').format(_totalIncomeSum)}',
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
                        const TextSpan(text: '?úÏùµ : ', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
                        TextSpan(text: '??{NumberFormat('#,###').format(_totalNetProfitSum)}', style: TextStyle(color: Color(0xFFFFC700), fontSize: 13)),
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
                        const TextSpan(text: 'ÏßÄÏ∂?: ', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                        TextSpan(text: '-??{NumberFormat('#,###').format(_totalExpenseSum)}', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
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
          totalCount: _filteredTotalCount,
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
            startSnippet: '$prog ¬∑ $time\n(${startLoc.isNotEmpty ? startLoc : 'Ï£ºÏÜå ?ïÎ≥¥ ?ÜÏùå'})',
            endSnippet: '$prog ¬∑ $time\n(${endLoc.isNotEmpty ? endLoc : 'Ï£ºÏÜå ?ïÎ≥¥ ?ÜÏùå'})',
          ),
        );
      }
    }

    if (segments.isEmpty) {
      if (!mounted) return;
      showDbrosSnackBar(context, '?¥Îãπ ?†Ïßú??Í∏∞Î°ù??Ï¢åÌëúÍ∞Ä ?ÜÏäµ?àÎã§.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatsRouteMapPage(
          periodLabel: '?ºÍ∞Ñ',
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
      showDbrosSnackBar(context, isNext ? '?§Ïùå Í∑ºÎ¨¥?ºÏ?Í∞Ä ?ÜÏäµ?àÎã§.' : '?¥Ï†Ñ Í∑ºÎ¨¥?ºÏ?Í∞Ä ?ÜÏäµ?àÎã§.');
    }
  }
}

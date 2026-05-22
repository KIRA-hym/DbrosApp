import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/feature_flags.dart';
import '../config/home_promo_config.dart';
import '../services/db_helper.dart';
import '../services/youtube_rss_service.dart';
import '../utils/responsive_layout.dart';
import '../utils/work_date_utils.dart';
import '../widgets/bordered_section.dart';
import '../widgets/home_daily_charts_panel.dart';
import '../widgets/responsive_body.dart';
import '../widgets/drive_log_source_chip.dart';
import 'log_list_page.dart';
import 'single_call_card_page.dart';
import 'multi_call_card_page.dart';
import '../expense_main_wrapper.dart';
import '../widgets/waiting_fee_bottom_sheet.dart';
import 'nearby_hotspot_map_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  /// DB 일지 저장·삭제 후 홈 요약·최근일지 갱신 (탭 전환 없이도 반영)
  static void requestRefresh() {
    _HomePageState._active?.requestLoadHomeData();
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static _HomePageState? _active;
  int _todayCount = 0;
  int _todayNet = 0;
  int _todayExpenses = 0;
  bool _isLoading = true;
  Timer? _workDateTick;
  /// 홈 상단·DB 집계: 유효 근무일 `yyyy-MM-dd` (근무일 `work_date` 기준)
  String _homeCalendarYmd = '';
  List<Map<String, dynamic>> _recentLogs = const [];
  int _recentLogIndex = 0;
  Timer? _recentLogTicker;
  String? _latestYoutubeVideoId;
  String _latestYoutubeTitle = '';
  String _latestYoutubeChannelName = '';
  String _latestYoutubePublishedDot = '';
  bool _youtubeLoading = true;
  final GlobalKey<HomeDailyChartsPanelState> _chartsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _active = this;
    WidgetsBinding.instance.addObserver(this);
    _workDateTick = Timer.periodic(const Duration(minutes: 1), (_) => _rollWorkDateIfNeeded());
    _loadHomeData();
    _loadYoutubeBanner();
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    WidgetsBinding.instance.removeObserver(this);
    _workDateTick?.cancel();
    _recentLogTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadHomeData();
      _loadYoutubeBanner();
      _chartsKey.currentState?.reload();
    }
  }

  void requestLoadHomeData() {
    if (mounted) _loadHomeData();
    _chartsKey.currentState?.reload();
  }

  void _rollWorkDateIfNeeded() {
    final cal = WorkDateUtils.effectiveWorkDateYmd();
    if (cal != _homeCalendarYmd) {
      _loadHomeData();
    }
  }

  void _restartRecentLogTicker() {
    _recentLogTicker?.cancel();
    _recentLogIndex = 0;
    if (_recentLogs.length <= 1) return;
    _recentLogTicker = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted || _recentLogs.isEmpty) return;
      setState(() {
        _recentLogIndex = (_recentLogIndex + 1) % _recentLogs.length;
      });
    });
  }

  Future<void> _loadHomeData() async {
    final String cal = WorkDateUtils.effectiveWorkDateYmd();
    Map<String, dynamic> stats = {'count': 0, 'net': 0, 'expenses': 0};
    List<Map<String, dynamic>> recent = [];

    try {
      stats = await DriveLogDatabase.instance.getTodayStatsByWorkDate(cal);
      recent = await DriveLogDatabase.instance.getRecentLogs(limit: 5);
    } catch (e) {
      debugPrint('Web/Mock fallback DB error: $e');
    }

    if (!mounted) return;
    setState(() {
      _homeCalendarYmd = cal;
      _todayCount = (stats['count'] as int?) ?? 0;
      _todayNet = (stats['net'] as int?) ?? 0;
      _todayExpenses = (stats['expenses'] as int?) ?? 0;
      _recentLogs = recent;
      _recentLogIndex = 0;
      _isLoading = false;
    });
    _restartRecentLogTicker();
  }

  Future<void> _loadYoutubeBanner() async {
    final raw = kHomeYoutubeVideoId.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _latestYoutubeVideoId = null;
        _latestYoutubeChannelName = '';
        _latestYoutubePublishedDot = '';
        _youtubeLoading = false;
      });
      return;
    }

    String? latest;
    String latestTitle = '';
    String latestChannel = '';
    String latestPublishedDot = '';
    if (isHomeYoutubeChannelId(raw)) {
      final meta = await YoutubeRssService.fetchLatestVideoMetaCached(raw);
      latest = meta?.id;
      if (meta != null) {
        if (meta.title.isNotEmpty) latestTitle = meta.title;
        latestChannel = meta.channelName;
        latestPublishedDot = meta.publishedDot;
      }
      if (latest != null &&
          latest.length == 11 &&
          latestTitle.isEmpty &&
          latestChannel.isEmpty) {
        final fill = await YoutubeRssService.fetchVideoMetaById(latest);
        if (fill != null) {
          latestTitle = fill.title;
          latestChannel = fill.channelName;
        }
      }
    } else if (raw.length == 11) {
      latest = raw;
      final oembed = await YoutubeRssService.fetchVideoMetaById(raw);
      if (oembed != null) {
        latestTitle = oembed.title;
        latestChannel = oembed.channelName;
      }
    }

    if (!mounted) return;
    setState(() {
      _latestYoutubeVideoId = latest;
      _latestYoutubeTitle = latestTitle;
      _latestYoutubeChannelName = latestChannel;
      _latestYoutubePublishedDot = latestPublishedDot;
      _youtubeLoading = false;
    });
  }

  Future<void> _openYoutubeBanner() async {
    final raw = kHomeYoutubeVideoId.trim();
    if (_latestYoutubeVideoId != null && _latestYoutubeVideoId!.isNotEmpty) {
      final videoUrl = Uri.parse('https://www.youtube.com/watch?v=$_latestYoutubeVideoId');
      await launchUrl(videoUrl, mode: LaunchMode.externalApplication);
      return;
    }
    if (raw.isNotEmpty && isHomeYoutubeChannelId(raw)) {
      final channelUrl = Uri.parse('https://www.youtube.com/channel/$raw');
      await launchUrl(channelUrl, mode: LaunchMode.externalApplication);
    }
  }

  void _openTodayDailyList() {
    final dateStr = WorkDateUtils.effectiveWorkDateYmd();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DailyLogListPage(dateStr: dateStr, dateTitle: '근무일자: $dateStr'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpanded = ResponsiveLayout.isFoldOrTablet(context);
    final padding = ResponsiveLayout.horizontalPadding(context);
    final titleFontSize = isExpanded ? 20.0 : 18.0;
    final sectionGap = isExpanded ? 14.0 : 10.0;

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121418),
        elevation: 0,
        titleSpacing: 20.0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: titleFontSize + 70,
                    child: Image.asset(
                      'assets/title.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 30.0, left: 4.0, right: 4.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () {
                          if (!kExpenseOwnerOnly) return;
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              settings: const RouteSettings(name: '/expense_main'),
                              builder: (_) => const ExpenseMainWrapper(),
                            ),
                          );
                        },
                        child: Text(
                          "운행 일지 관리",
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFFFC700),
                                fontSize: 20.0,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        centerTitle: false,
      ),
      body: ResponsiveBody(
        fullWidthWhenExpanded: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
            : Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (isExpanded) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 11,
                                  child: _buildTodaySummaryCard(),
                                ),
                                SizedBox(height: sectionGap),
                                Expanded(
                                  flex: 13,
                                  child: HomeDailyChartsPanel(key: _chartsKey),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: sectionGap),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 10,
                                  child: _buildQuickActions(),
                                ),
                                SizedBox(height: sectionGap),
                                Expanded(
                                  flex: 10,
                                  child: _buildRecentLogSection(),
                                ),
                                SizedBox(height: sectionGap),
                                Expanded(
                                  flex: 6,
                                  child: _buildYoutubeSection(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 34,
                          child: _buildTodaySummaryCard(),
                        ),
                        SizedBox(height: sectionGap),
                        Expanded(
                          flex: 24,
                                  child: _buildQuickActions(),
                        ),
                        SizedBox(height: sectionGap),
                        Expanded(
                          flex: 20,
                          child: _buildRecentLogSection(),
                        ),
                        SizedBox(height: sectionGap),
                        Expanded(
                          flex: 14,
                          child: _buildYoutubeSection(),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  /// 2×2 요약 칸 — 제목 16px·값 14px(태블릿 +2), 레이아웃 치수는 카드 크기 기준.
  ({
    double cell,
    double rowGap,
    double colGap,
    double innerPad,
    double titleTopInset,
    double titleFs,
    double valueFs,
    double iconSz,
    double headerBlockH,
    double valueGap,
  }) _homeSummaryGridMetrics(
    BuildContext context,
    double w,
    double h,
    double titleFs,
    double valueFs,
  ) {
    final scaledTitleFs = ResponsiveLayout.layoutFontSize(context, titleFs);
    final rowGap = (w * 0.022).clamp(8.0, 14.0);
    final colGap = (w * 0.022).clamp(8.0, 14.0);
    final cw = (w - colGap) / 2;
    final ch = (h - rowGap) / 2;
    final cell = math.min(cw, ch);
    final titleTopInset = (cell * 0.05).clamp(6.0, 12.0);
    final valueGap = (cell * 0.04).clamp(4.0, 10.0);
    final headerBlockH = titleTopInset + scaledTitleFs * 1.12;
    return (
      cell: cell,
      rowGap: rowGap,
      colGap: colGap,
      innerPad: (cell * 0.06).clamp(16.0, 20.0),
      titleTopInset: titleTopInset,
      titleFs: titleFs,
      valueFs: valueFs,
      iconSz: (cell * 0.18).clamp(20.0, 42.0),
      headerBlockH: headerBlockH,
      valueGap: valueGap,
    );
  }

  TextStyle _homeSummaryTitleStyle(BuildContext context) {
    return ResponsiveLayout.sectionTitleTextStyle(context);
  }

  TextStyle _homeSummaryValueStyle(BuildContext context, {required Color color}) {
    return ResponsiveLayout.sectionTitleTextStyle(context).copyWith(
      color: color,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5,
    );
  }

  Widget _homeSummaryHeaderBlock({
    required ({
      double cell,
      double rowGap,
      double colGap,
      double innerPad,
      double titleTopInset,
      double titleFs,
      double valueFs,
      double iconSz,
      double headerBlockH,
      double valueGap,
    }) metrics,
    required Widget titleRow,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.headerBlockH),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(top: metrics.titleTopInset),
          child: titleRow,
        ),
      ),
    );
  }

  Widget _homeSummaryValueLine({
    required BuildContext context,
    required ({
      double cell,
      double rowGap,
      double colGap,
      double innerPad,
      double titleTopInset,
      double titleFs,
      double valueFs,
      double iconSz,
      double headerBlockH,
      double valueGap,
    }) metrics,
    required String value,
    required Color valueColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: metrics.valueGap),
          Expanded(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _homeSummaryValueStyle(context, color: valueColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrencyK(int value) {
    if (value == 0) return '0';
    if (value % 1000 == 0) {
      return '${value ~/ 1000}K';
    } else {
      String formatted = (value / 1000.0).toStringAsFixed(1);
      if (formatted.endsWith('.0')) {
        formatted = formatted.substring(0, formatted.length - 2);
      }
      return '${formatted}K';
    }
  }

  Widget _buildTodaySummaryCard() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final outerPad = isTablet ? 24.0 : 16.0;

    final DateTime workDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    final String dateCompact = DateFormat('M월 d일').format(workDay);
    final String weekdayLong = DateFormat('EEEE', 'ko').format(workDay);

    return Container(
      decoration: BorderedSection.decoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: const Color(0xFF1F222A),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openTodayDailyList,
        splashColor: const Color(0xFFFFC700).withValues(alpha: 0.12),
        highlightColor: Colors.white10,
        child: Padding(
          padding: EdgeInsets.all(outerPad),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final titleFs = ResponsiveLayout.sectionTitleFontSize(context);
              final valueFs = ResponsiveLayout.summaryValueFontSize(context);
              final m = _homeSummaryGridMetrics(
                context,
                constraints.maxWidth,
                constraints.maxHeight,
                titleFs,
                valueFs,
              );

              return Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildSummaryTextCell(
                            context: context,
                            metrics: m,
                            title: '오늘 순익',
                            value: NumberFormat('#,###').format(_todayNet),
                            valueColor: const Color(0xFFFFC700),
                            icon: Icons.account_balance_wallet,
                          ),
                        ),
                        SizedBox(width: m.colGap),
                        Expanded(
                          child: _buildSummaryTextCell(
                            context: context,
                            metrics: m,
                            title: dateCompact,
                            value: weekdayLong,
                            valueColor: Colors.white,
                            icon: Icons.calendar_today,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: m.rowGap),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildMirrorSummaryCell(
                            context: context,
                            icon: Icons.local_taxi,
                            label: '운행 건수',
                            value: '$_todayCount건',
                            valueColor: const Color(0xFFFFC700),
                            metrics: m,
                          ),
                        ),
                        SizedBox(width: m.colGap),
                        Expanded(
                          child: _buildMirrorSummaryCell(
                            context: context,
                            icon: Icons.payments_outlined,
                            label: '오늘 지출',
                            value: NumberFormat('#,###').format(_todayExpenses),
                            valueColor: const Color(0xFFFF5252),
                            metrics: m,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildSummaryTextCell({
    required BuildContext context,
    required ({
      double cell,
      double rowGap,
      double colGap,
      double innerPad,
      double titleTopInset,
      double titleFs,
      double valueFs,
      double iconSz,
      double headerBlockH,
      double valueGap,
    }) metrics,
    required String title,
    required String value,
    required Color valueColor,
    IconData? icon,
  }) {
    final isExpanded = ResponsiveLayout.isFoldOrTablet(context);
    final titleFs = metrics.titleFs + (isExpanded ? 0.0 : 2.0);
    final valueFs = metrics.valueFs + (isExpanded ? 0.0 : 2.0);
    final hPad = isExpanded ? 24.0 : 16.0;
    final vPad = isExpanded ? 20.0 : 14.0;
    final innerGap = isExpanded ? 16.0 : math.max(4.0, titleFs * 0.3);
    const titleTopInset = 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final scaledTitle = ResponsiveLayout.layoutFontSize(context, titleFs);
        final scaledValue = ResponsiveLayout.layoutFontSize(context, valueFs);
        final minContentH = scaledTitle * 1.12 + innerGap + scaledValue * 1.12 + vPad * 2 + titleTopInset;
        final scale = (!h.isFinite || h <= 0 || h >= minContentH)
            ? 1.0
            : (h / minContentH).clamp(0.72, 1.0);
        final effTitleFs = titleFs * scale;
        final effValueFs = effTitleFs + (2.0 * scale);
        final effVPad = (vPad * scale).clamp(2.0, vPad);
        final effTop = (titleTopInset * scale).clamp(0.0, titleTopInset);
        final effGap = (innerGap * scale).clamp(1.0, innerGap);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF16181D),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.fromLTRB(hPad, effVPad + effTop, hPad, effVPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: const Color(0xFFFFC700), size: effTitleFs * 1.2),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _homeSummaryTitleStyle(context).copyWith(
                        fontSize: effTitleFs,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: effGap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomRight,
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _homeSummaryValueStyle(context, color: valueColor).copyWith(
                            fontSize: effValueFs,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMirrorSummaryCell({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    required ({
      double cell,
      double rowGap,
      double colGap,
      double innerPad,
      double titleTopInset,
      double titleFs,
      double valueFs,
      double iconSz,
      double headerBlockH,
      double valueGap,
    }) metrics,
  }) {
    return _buildSummaryTextCell(
      context: context,
      metrics: metrics,
      title: label,
      value: value,
      valueColor: valueColor,
      icon: icon,
    );
  }

  ({double textFs, double iconSz, double gap, double waitingBtnH}) _homeQuickActionsMetrics(
    double w,
    double h,
  ) {
    final gap = (w * 0.025).clamp(8.0, 12.0);
    final waitingBtnH = (h * 0.24).clamp(36.0, 48.0);
    final topH = math.max(48.0, h - gap - waitingBtnH);
    final cw = (w - gap) / 2;
    final cell = math.min(cw, topH);
    const textFs = 14.0;
    final iconSz = (cell * 0.22).clamp(22.0, 36.0);
    return (textFs: textFs, iconSz: iconSz, gap: gap, waitingBtnH: waitingBtnH);
  }

  Widget _buildQuickActions() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final outerPadding = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(outerPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final q = _homeQuickActionsMetrics(constraints.maxWidth, constraints.maxHeight);
          final textFs = isTablet ? q.textFs + 5.0 : q.textFs;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _quickActionButton(
                        Icons.credit_card,
                        '콜카드\n단건등록',
                        textFs,
                        q.iconSz,
                    () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SingleCallCardForm(),
                        ),
                      );
                      _loadHomeData();
                    },
                  ),
                ),
                    SizedBox(width: q.gap),
                    Expanded(
                      child: _quickActionButton(
                        Icons.credit_card,
                        '콜카드\n다중등록',
                        textFs,
                        q.iconSz,
                    () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MultiCallCardForm(),
                        ),
                      );
                      _loadHomeData();
                    },
                  ),
                ),
                  ],
                ),
              ),
              SizedBox(height: q.gap),
              SizedBox(
                height: q.waitingBtnH,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFC700),
                    side: const BorderSide(color: Color(0xFFFFC700)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => WaitingFeeBottomSheet.show(context),
                  icon: Icon(Icons.timer_outlined, size: textFs * 1.2),
                  label: Text(
                    '대기비용 계산',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: textFs),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildYoutubeSection() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final outerPadding = 16.0;
    final titleFs = isTablet ? 13.5 : 12.0;

    return Container(
      decoration: BorderedSection.decoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: const Color(0xFF1F222A),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openYoutubeBanner,
        child: Padding(
          padding: EdgeInsets.all(outerPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '명예 대리 유튜버',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'GmarketSans',
                  color: const Color(0xFFFFC700),
                  fontWeight: FontWeight.w700,
                  fontSize: titleFs,
                  height: 1.2,
                ),
              ),
              SizedBox(height: isTablet ? 8 : 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, rowConstraints) {
                    final thumbW = math.min(
                      isTablet ? 176.0 : 152.0,
                      rowConstraints.maxWidth * (isTablet ? 0.42 : 0.38),
                    );
                    return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: thumbW,
                        height: double.infinity,
                        child: _latestYoutubeVideoId == null
                            ? Container(
                                color: const Color(0xFF16181D),
                                child: const Icon(Icons.ondemand_video, color: Color(0xFFFFC700)),
                              )
                            : Image.network(
                                'https://i.ytimg.com/vi/$_latestYoutubeVideoId/mqdefault.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: const Color(0xFF16181D),
                                  child: const Icon(Icons.ondemand_video, color: Color(0xFFFFC700)),
                                ),
                              ),
                      ),
                    ),
                    SizedBox(width: isTablet ? 12 : 10),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openYoutubeBanner,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: isTablet ? 8 : 6),
                            child: _youtubeLoading
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFC700)),
                                    ),
                                  )
                                : (_latestYoutubeTitle.isEmpty &&
                                        _latestYoutubeChannelName.isEmpty &&
                                        _latestYoutubePublishedDot.isEmpty
                                    ? const SizedBox.shrink()
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_latestYoutubeChannelName.isNotEmpty ||
                                                _latestYoutubePublishedDot.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        _latestYoutubeChannelName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                              color: const Color(0xFF9FA3AE),
                                                              height: 1.2,
                                                            ),
                                                      ),
                                                    ),
                                                    if (_latestYoutubePublishedDot.isNotEmpty) ...[
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        _latestYoutubePublishedDot,
                                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                              color: const Color(0xFF9FA3AE),
                                                              height: 1.2,
                                                            ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            if (_latestYoutubeTitle.isNotEmpty)
                                              Text(
                                                _latestYoutubeTitle,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                      color: Colors.white,
                                                      height: 1.2,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      )),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  Widget _buildRecentLogSection() {
    final isTablet = ResponsiveLayout.isTablet(context);
    final isPhoneFolded = ResponsiveLayout.isPhoneLayout(context);
    final outerPadding = isTablet ? 14.0 : 12.0;
    final recentTitleFs = ResponsiveLayout.sectionTitleFontSize(context) + (isTablet ? 2.0 : 0.0);
    final bodyFs = ResponsiveLayout.summaryValueFontSize(context);
    final titleStyle = TextStyle(
      fontFamily: 'GmarketSans',
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: recentTitleFs,
      height: 1.12,
    );

    if (_recentLogs.isEmpty) {
      return Container(
        decoration: BorderedSection.decoration(),
        padding: EdgeInsets.all(outerPadding),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '최근운행일지\n아직 등록된 운행일지가 없습니다.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6E717C), height: 1.35),
          ),
        ),
      );
    }

    final log = _recentLogs[_recentLogIndex.clamp(0, _recentLogs.length - 1)];
    final gross = _asInt(log['gross_fare']);
    final tip = _asInt(log['waypoint_tip']);
    final fee = _asInt(log['fee']);
    final transport = _asInt(log['transport_cost']);
    final income = gross + tip;
    final expense = fee + transport;
    final net = _asInt(log['net_income']);
    final time = (log['drive_time'] ?? '').toString();
    final workDateLabel =
        (log['work_date']?.toString().trim().isNotEmpty == true ? log['work_date'] : log['drive_date'])?.toString() ?? '';
    final program = (log['program'] ?? '-').toString();
    final start = (log['start_location'] ?? '').toString().trim();
    final waypoint = (log['waypoint'] ?? '').toString().trim();
    final end = (log['end_location'] ?? '').toString().trim();
    final hasWaypoint = waypoint.isNotEmpty;
    final metaTextStyle = TextStyle(
      color: Colors.white70,
      fontWeight: FontWeight.w500,
      height: 1.1,
      fontSize: bodyFs,
    );
    final routeTextStyle = TextStyle(
      color: Colors.white70,
      fontWeight: FontWeight.w500,
      height: 1.1,
      fontSize: bodyFs,
    );
    final moneyBaseStyle = TextStyle(
      fontWeight: FontWeight.w700,
      height: 1.1,
      fontSize: bodyFs,
    );

    return Container(
      decoration: BorderedSection.decoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTodayDailyList,
          child: Padding(
            padding: EdgeInsets.all(outerPadding),
            child: Row(
              children: [
                if (kMapFeaturesEnabled) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NearbyHotspotMapPage()),
                        );
                      },
                      child: Container(
                        width: isTablet ? 74 : 62,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFC700).withValues(alpha: 0.3)),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, color: const Color(0xFFFFC700), size: isTablet ? 26 : 22),
                            SizedBox(height: isTablet ? 4 : 2),
                            Text('지도', style: TextStyle(color: const Color(0xFFFFC700), fontSize: isTablet ? 11 : 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 12 : 10),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentRowCount = hasWaypoint ? 5 : 4;
                      final rowPad = EdgeInsets.symmetric(
                        vertical: isPhoneFolded
                            ? 0.0
                            : (constraints.maxHeight * 0.01).clamp(1.0, 4.0),
                      );

                      Widget contentRow(Widget child) {
                        return Expanded(
                          child: Padding(
                            padding: rowPad,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: child,
                            ),
                          ),
                        );
                      }

                      final contentRows = <Widget>[
                        contentRow(
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: metaTextStyle,
                                    children: [
                                      TextSpan(text: '$workDateLabel $time · '),
                                      TextSpan(
                                        text: program,
                                        style: metaTextStyle.copyWith(color: Colors.greenAccent),
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DriveLogSourceChip(
                                registrationSource: log['registration_source']?.toString(),
                              ),
                            ],
                          ),
                        ),
                        contentRow(
                          Text(
                            start.isEmpty ? '출발지 : 정보 없음' : '출발지 : $start',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: routeTextStyle,
                          ),
                        ),
                        contentRow(
                          Text(
                            hasWaypoint
                                ? '경유지 : $waypoint'
                                : (end.isEmpty ? '도착지 : 정보 없음' : '도착지 : $end'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: routeTextStyle,
                          ),
                        ),
                        if (hasWaypoint)
                          contentRow(
                            Text(
                              end.isEmpty ? '도착지 : 정보 없음' : '도착지 : $end',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: routeTextStyle,
                            ),
                          ),
                        contentRow(
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        '수입 ${NumberFormat('#,###').format(income)}',
                                        style: moneyBaseStyle.copyWith(color: Colors.lightBlueAccent),
                                      ),
                                      if (expense > 0) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '지출 ${NumberFormat('#,###').format(expense)}',
                                          style: moneyBaseStyle.copyWith(color: const Color(0xFFFF5252)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '순익 ${NumberFormat('#,###').format(net)}',
                                style: moneyBaseStyle.copyWith(color: const Color(0xFFFFC700)),
                              ),
                            ],
                          ),
                        ),
                      ];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '최근운행일지',
                            style: titleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: isPhoneFolded ? 2 : 4),
                          Expanded(
                            child: Column(
                              children: contentRows.take(contentRowCount).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionButton(
    IconData icon,
    String label,
    double textFs,
    double iconSz,
    VoidCallback onTap,
  ) {
    return SizedBox.expand(
      child: Material(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all((textFs * 0.35).clamp(8.0, 12.0)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFFFFC700), size: iconSz),
                SizedBox(height: (textFs * 0.25).clamp(4.0, 8.0)),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: textFs,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

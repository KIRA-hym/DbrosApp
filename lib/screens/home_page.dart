import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/ad_banner_widget.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/today_stats_provider.dart';
import '../config/feature_flags.dart';
import '../config/home_promo_config.dart';
import '../services/notice_service.dart';
import '../services/settings_service.dart';
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
import 'call_point_map_page.dart';
import '../utils/pro_feature_guard.dart';
import '../services/feature_usage_service.dart';

/// 앱 프로세스 생존 동안 공지 닫힘 상태를 유지하는 최상위 전역 변수.
/// static 필드를 State 안에 두면 핫리스타트 등으로 초기화될 수 있으므로 파일 레벨로 분리.
bool _homeNoticeClosed = false;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final bool _isLoading = false;
  Timer? _workDateTick;

  List<Map<String, dynamic>> _recentLogs = const [];
  int _recentLogIndex = 0;
  Timer? _recentLogTicker;
  String? _latestYoutubeVideoId;
  String _latestYoutubeTitle = '';
  String _latestYoutubeChannelName = '';
  String _latestYoutubePublishedDot = '';
  bool _youtubeLoading = true;
  final GlobalKey<HomeDailyChartsPanelState> _chartsKey = GlobalKey();

  List<Map<String, dynamic>> _activeNotices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workDateTick = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _rollWorkDateIfNeeded(),
    );

    // 초기 데이터 수동 요청 대신 Provider가 이미 데이터 갱신을 하도록 main에서 처리함.
    // Provider 초기 로딩 기다림
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restartRecentLogTicker();
    });
    _loadYoutubeBanner();
    _loadNotices();
  }

  void _loadNotices() async {
    final notices = await NoticeService.instance.fetchActiveNotices();
    if (mounted) {
      setState(() {
        _activeNotices = notices;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workDateTick?.cancel();
    _recentLogTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      TodayStatsProvider.instance.refresh();
      _loadYoutubeBanner();
      _loadNotices();
      _chartsKey.currentState?.reload();
      if (_workDateTick == null || !_workDateTick!.isActive) {
        _workDateTick = Timer.periodic(
          const Duration(minutes: 1),
          (_) => _rollWorkDateIfNeeded(),
        );
      }
      _restartRecentLogTicker();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _workDateTick?.cancel();
      _recentLogTicker?.cancel();
    }
  }

  void _rollWorkDateIfNeeded() {
    final cal = WorkDateUtils.effectiveWorkDateYmd();
    if (cal != TodayStatsProvider.instance.currentWorkDateYmd) {
      TodayStatsProvider.instance.refresh();
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

  // _loadHomeData() is now replaced by TodayStatsProvider.refresh()

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
      final videoUrl = Uri.parse(
        'https://www.youtube.com/watch?v=$_latestYoutubeVideoId',
      );
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
        builder: (_) => DailyLogListPage(dateStr: dateStr, dateTitle: dateStr),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsProvider = Provider.of<TodayStatsProvider>(context);

    // Ensure ticker updates if recentLogs changes
    if (_recentLogs.length != statsProvider.recentLogs.length) {
      _recentLogs = statsProvider.recentLogs;
      _restartRecentLogTicker();
    } else {
      _recentLogs = statsProvider.recentLogs;
    }

    final isExpanded = ResponsiveLayout.isFoldOrTablet(context);
    final padding = ResponsiveLayout.horizontalPadding(context);
    final titleFontSize = isExpanded ? 20.0 : 18.0;
    final sectionGap = isExpanded ? 14.0 : 10.0;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF121418),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121418),
            elevation: 0,
            toolbarHeight: 70,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: SizedBox(
              height: 70, // Match toolbar height
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: padding,
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(20),
                      child: const Icon(Icons.account_circle, color: Colors.white, size: 40),
                    ),
                  ),
                  SizedBox(
                    height: titleFontSize + 40,
                    child: Image.asset(
                      'assets/title.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    right: padding,
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(20),
                      child: const Icon(Icons.notifications_none, color: Color(0xFFFFC700), size: 30),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: ResponsiveBody(
                  fullWidthWhenExpanded: true,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFC700),
                          ),
                        )
                      : Padding(
                          padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              if (isExpanded) {
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildTodaySummaryCard(),
                                          SizedBox(height: sectionGap),
                                          Expanded(
                                            flex: 13,
                                            child: HomeDailyChartsPanel(
                                              key: _chartsKey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: sectionGap),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            height: 60,
                                            child: _buildUtilsRow(),
                                          ),
                                          SizedBox(height: sectionGap),
                                          SizedBox(
                                            height: 85,
                                            child: _buildRegisterRow(),
                                          ),
                                          SizedBox(height: sectionGap),
                                          const AdBannerWidget(),
                                          SizedBox(height: sectionGap),
                                          Expanded(
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
                                  _buildTodaySummaryCard(),
                                  SizedBox(height: sectionGap),
                                  SizedBox(
                                    height: 60,
                                    child: _buildUtilsRow(),
                                  ),
                                  SizedBox(height: sectionGap),
                                  SizedBox(
                                    height: 85,
                                    child: _buildRegisterRow(),
                                  ),
                                  SizedBox(height: sectionGap),
                                  const AdBannerWidget(),
                                  SizedBox(height: sectionGap),
                                  Expanded(
                                    child: _buildYoutubeSection(),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (!_homeNoticeClosed && _activeNotices.isNotEmpty)
          _buildFloatingNoticeBanner(),
      ],
    );
  }

  Widget _buildFloatingNoticeBanner() {
    final noticeMap = _activeNotices.first;
    final title = noticeMap['title'] as String? ?? '공지사항';
    final content = (noticeMap['content'] as String? ?? '').replaceAll(
      '\\n',
      '\n',
    );
    final isImportant = noticeMap['isImportant'] == true;
    final noticeMsg = '[$title]\n$content';

    return Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(context).padding.top + 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1F222A).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFF5252).withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.campaign,
                color: isImportant
                    ? const Color(0xFFFF5252)
                    : const Color(0xFFFFC700),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1.0),
                  child: Text(
                    noticeMsg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _homeNoticeClosed = true;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.close, color: Color(0xFF9FA3AE), size: 18),
                ),
              ),
            ],
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
  })
  _homeSummaryGridMetrics(
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

  TextStyle _homeSummaryValueStyle(
    BuildContext context, {
    required Color color,
  }) {
    return ResponsiveLayout.sectionTitleTextStyle(
      context,
    ).copyWith(color: color, fontWeight: FontWeight.bold, letterSpacing: -0.5);
  }

  Widget _buildTodaySummaryCard() {
    final statsProvider = Provider.of<TodayStatsProvider>(context);
    final DateTime workDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    final String dateFull = "${workDay.year}년 ${workDay.month}월 ${workDay.day}일 (${DateFormat('E', 'ko').format(workDay)})";

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2F36)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTodayDailyList,
          splashColor: const Color(0xFFFFC700).withValues(alpha: 0.12),
          highlightColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateFull,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 14,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      '오늘 순익',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          NumberFormat('#,###').format(statsProvider.todayNet),
                          style: const TextStyle(
                            color: Color(0xFFFFC700),
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '원',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '운행건수',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${statsProvider.todayLogs}건',
                              style: const TextStyle(
                                color: Color(0xFF4DABF7),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.white.withValues(alpha: 0.1),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '지출',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${NumberFormat('#,###').format(statsProvider.todayExpenses)}원',
                              style: const TextStyle(
                                color: Color(0xFFFF5252),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
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
  }

  Widget _buildUtilsRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => WaitingFeeBottomSheet.show(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F222A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFC700)),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, color: Color(0xFFFFC700), size: 20),
                  SizedBox(width: 6),
                  Text('대기비용 계산', style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () {
              if (!kMapFeaturesEnabled) return;
              ProFeatureGuard.checkAndRun(
                context: context,
                featureKey: 'call_map',
                canUseFree: FeatureUsageService.canUseCallMapFree,
                canUseWithAd: FeatureUsageService.canUseCallMapWithAd,
                onGranted: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CallPointMapPage()));
                },
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F222A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFC700)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map, color: Color(0xFFFFC700), size: 20),
                  const SizedBox(width: 6),
                  Text('주변 콜맵', style: TextStyle(color: kMapFeaturesEnabled ? const Color(0xFFFFC700) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SingleCallCardForm()));
              TodayStatsProvider.instance.refresh();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F222A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2C2F36)),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.credit_card, color: Color(0xFFFFC700), size: 32),
                  SizedBox(height: 10),
                  Text('콜카드 단건등록', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiCallCardForm()));
              TodayStatsProvider.instance.refresh();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1F222A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2C2F36)),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_add_check, color: Color(0xFFFFC700), size: 32),
                  SizedBox(height: 10),
                  Text('콜카드 다중등록', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ],
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
                                      alignment: Alignment.center,
                                      child: const Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.open_in_new,
                                            color: Color(0xFF9FA3AE),
                                            size: 28,
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            '채널 방문하기',
                                            style: TextStyle(
                                              color: Color(0xFF9FA3AE),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Image.network(
                                      'https://i.ytimg.com/vi/$_latestYoutubeVideoId/mqdefault.jpg',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: const Color(0xFF16181D),
                                        alignment: Alignment.center,
                                        child: const Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.open_in_new,
                                              color: Color(0xFF9FA3AE),
                                              size: 28,
                                            ),
                                            SizedBox(height: 6),
                                            Text(
                                              '채널 방문하기',
                                              style: TextStyle(
                                                color: Color(0xFF9FA3AE),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
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
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isTablet ? 8 : 6,
                                  ),
                                  child: _youtubeLoading
                                      ? const Align(
                                          alignment: Alignment.centerLeft,
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFFFC700),
                                            ),
                                          ),
                                        )
                                      : (_latestYoutubeTitle.isEmpty &&
                                                _latestYoutubeChannelName
                                                    .isEmpty &&
                                                _latestYoutubePublishedDot
                                                    .isEmpty
                                            ? const SizedBox.shrink()
                                            : Align(
                                                alignment: Alignment.centerLeft,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (_latestYoutubeChannelName
                                                            .isNotEmpty ||
                                                        _latestYoutubePublishedDot
                                                            .isNotEmpty)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 6,
                                                            ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                _latestYoutubeChannelName,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: Theme.of(context)
                                                                    .textTheme
                                                                    .labelMedium
                                                                    ?.copyWith(
                                                                      color: const Color(
                                                                        0xFF9FA3AE,
                                                                      ),
                                                                      height:
                                                                          1.2,
                                                                    ),
                                                              ),
                                                            ),
                                                            if (_latestYoutubePublishedDot
                                                                .isNotEmpty) ...[
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Text(
                                                                _latestYoutubePublishedDot,
                                                                style: Theme.of(context)
                                                                    .textTheme
                                                                    .labelMedium
                                                                    ?.copyWith(
                                                                      color: const Color(
                                                                        0xFF9FA3AE,
                                                                      ),
                                                                      height:
                                                                          1.2,
                                                                    ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    if (_latestYoutubeTitle
                                                        .isNotEmpty)
                                                      Text(
                                                        _latestYoutubeTitle,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleSmall
                                                            ?.copyWith(
                                                              color:
                                                                  Colors.white,
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
    final recentTitleFs =
        ResponsiveLayout.sectionTitleFontSize(context) + (isTablet ? 2.0 : 0.0);
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF6E717C),
              height: 1.35,
            ),
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
        (log['work_date']?.toString().trim().isNotEmpty == true
                ? log['work_date']
                : log['drive_date'])
            ?.toString() ??
        '';
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
                                        style: metaTextStyle.copyWith(
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DriveLogSourceChip(
                                registrationSource: log['registration_source']
                                    ?.toString(),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        '수입 ${NumberFormat('#,###').format(income)}',
                                        style: moneyBaseStyle.copyWith(
                                          color: Colors.lightBlueAccent,
                                        ),
                                      ),
                                      if (expense > 0) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '지출 ${NumberFormat('#,###').format(expense)}',
                                          style: moneyBaseStyle.copyWith(
                                            color: const Color(0xFFFF5252),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '순익 ${NumberFormat('#,###').format(net)}',
                                style: moneyBaseStyle.copyWith(
                                  color: const Color(0xFFFFC700),
                                ),
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
                              children: contentRows
                                  .take(contentRowCount)
                                  .toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (kMapFeaturesEnabled) ...[
                  SizedBox(width: isTablet ? 12 : 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        ProFeatureGuard.checkAndRun(
                          context: context,
                          featureKey: 'call_map',
                          canUseFree: FeatureUsageService.canUseCallMapFree,
                          canUseWithAd: FeatureUsageService.canUseCallMapWithAd,
                          onGranted: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CallPointMapPage(),
                              ),
                            );
                          },
                        );
                      },
                      child: Container(
                        width: isTablet ? 86 : 76,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFFFFC700,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.map,
                              color: const Color(0xFFFFC700),
                              size: isTablet ? 26 : 22,
                            ),
                            SizedBox(height: isTablet ? 4 : 2),
                            Text(
                              '주변 콜맵',
                              style: TextStyle(
                                color: const Color(0xFFFFC700),
                                fontSize: isTablet ? 11 : 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: label.contains('\n') ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: textFs,
                      height: 1.15,
                    ),
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

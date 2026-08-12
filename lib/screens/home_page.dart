import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../main_navigation.dart';
import '../widgets/ad_banner_widget.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:dbros_app/providers/notice_badge_provider.dart';
import 'package:dbros_app/screens/notice_list_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/today_stats_provider.dart';
import '../config/feature_flags.dart';
import '../utils/call_card_recognition_disclaimer.dart';
import '../config/home_promo_config.dart';
import '../services/notice_service.dart';
import '../services/font_size_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';
import '../services/db_helper.dart';
import '../services/youtube_rss_service.dart';
import '../providers/work_timer_provider.dart';
import '../utils/responsive_layout.dart';
import '../utils/work_date_utils.dart';
import '../widgets/app_glass_dialog.dart';
import '../widgets/bordered_section.dart';
import '../widgets/home_daily_charts_panel.dart';
import '../widgets/responsive_body.dart';
import '../widgets/drive_log_source_chip.dart';
import '../widgets/guide_content_widget.dart';
import 'log_list_page.dart';
import 'single_call_card_page.dart';
import 'multi_call_card_page.dart';
import 'my_info_page.dart';
import 'settings_page.dart';
import '../expense_main_wrapper.dart';
import '../widgets/waiting_fee_bottom_sheet.dart';
import 'call_point_map_page.dart';
import '../widgets/permission_disclosure_dialog.dart';
import '../widgets/onboarding_dialog.dart';
import '../utils/pro_feature_guard.dart';
import '../services/feature_usage_service.dart';
import '../services/auth_service.dart';
import '../services/apk_update_service.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../providers/guide_provider.dart';

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

  List<Map<String, dynamic>> _recentLogs = [];
  int _recentLogIndex = 0;
  Timer? _recentLogTicker;
  String? _latestYoutubeVideoId;
  String _latestYoutubeTitle = '';
  String _latestYoutubeChannelName = '';
  String _latestYoutubePublishedDot = '';
  bool _youtubeLoading = true;
  final GlobalKey<HomeDailyChartsPanelState> _chartsKey = GlobalKey();

  final GlobalKey _keyMyInfo = GlobalKey();
  final GlobalKey _keyWorkTimer = GlobalKey();
  final GlobalKey _keySingleRegister = GlobalKey();
  final GlobalKey _keyMultiRegister = GlobalKey();
  final GlobalKey _keyWaitingFee = GlobalKey();
  final GlobalKey _keyMap = GlobalKey();

  TutorialCoachMark? _tutorialCoachMark;

  WeatherInfo? _weatherInfo;

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
    ApkUpdateService.instance.checkForUpdate().then((_) {
      if (mounted) setState(() {});
    });
    _loadWeather();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        OnboardingDialog.showIfNeeded(context);
        
        final guideProvider = Provider.of<GuideProvider>(context, listen: false);
        guideProvider.addListener(_onGuideRequested);
        if (guideProvider.pendingGuideTarget == 'home') {
          _showHomeGuide();
        }
      }
    });
  }

  void _onGuideRequested() {
    if (!mounted) return;
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    if (guideProvider.pendingGuideTarget == 'home') {
      _showHomeGuide();
    }
  }

  void _showHomeGuide() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.clearGuide();

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "myInfo",
        keyTarget: _keyMyInfo,
    alignSkip: Alignment.bottomRight,
  contents: [
          TargetContent(
    align: ContentAlign.custom,
  customPosition: CustomTargetContentPosition(top: 0),
  builder: (context, controller) {
              return GuideContentWidget(
                title: "내 정보",
                description: "내 정보 확인과 앱 환경설정은 여기서 관리할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "workTimer",
        keyTarget: _keyWorkTimer,
    alignSkip: Alignment.bottomRight,
  contents: [
          TargetContent(
    align: ContentAlign.custom,
  customPosition: CustomTargetContentPosition(top: 0),
  builder: (context, controller) {
              return GuideContentWidget(
                title: "출근/퇴근",
                description: "운행 시작 전 '출근'을 누르고, 일이 끝나면 '퇴근'을 눌러 나의 근무시간을 정확하게 기록해 보세요!",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "singleRegister",
        keyTarget: _keySingleRegister,
    alignSkip: Alignment.bottomRight,
  contents: [
          TargetContent(
    align: ContentAlign.custom,
  customPosition: CustomTargetContentPosition(top: 0),
  builder: (context, controller) {
              return GuideContentWidget(
                title: "콜카드 단건등록",
                description: "콜카드를 첨부하면 내용을 자동으로 인식하여 셋팅해줍니다.\n\n단, 인식이 제대로 되지 않는 경우 잘못된 값이 입력되거나 일지가 등록되지 않을 수 있으니 주의해 주세요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "multiRegister",
        keyTarget: _keyMultiRegister,
    alignSkip: Alignment.bottomRight,
  contents: [
          TargetContent(
    align: ContentAlign.custom,
  customPosition: CustomTargetContentPosition(top: 0),
  builder: (context, controller) {
              return GuideContentWidget(
                title: "콜카드 다중등록",
                description: "콜카드를 여러 개 첨부하면 내용을 자동으로 인식하여 셋팅해줍니다.\n\n단, 인식이 제대로 되지 않는 경우 잘못된 값이 입력되거나 일지가 등록되지 않을 수 있으니 주의해 주세요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "waitingFee",
        keyTarget: _keyWaitingFee,
    alignSkip: Alignment.bottomRight,
  contents: [
          TargetContent(
    align: ContentAlign.custom,
  customPosition: CustomTargetContentPosition(top: 0),
  builder: (context, controller) {
              return GuideContentWidget(
                title: "대기비용 계산",
                description: "법인고객 대기시간이 발생했나요? 대기 시간에 따른 예상요금을 확인할 수 있어요.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "map",
        keyTarget: _keyMap,
    alignSkip: Alignment.bottomRight,
  contents: [
          TargetContent(
    align: ContentAlign.custom,
  customPosition: CustomTargetContentPosition(top: 0),
  builder: (context, controller) {
              return GuideContentWidget(
                title: "주변 콜맵",
                description: "현재 내 위치 주변에 대리 콜 포인트가 얼마나 있는지 지도로 한눈에 파악하세요!",
                controller: controller,
                isLast: true,
              );
            },
          ),
        ],
      ),
    ];

    _tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "건너뛰기",
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          try { Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst); } catch (_) {}
          mainTabEventController.add(4);
        });
        return true;
      },
      onSkip: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          try { Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst); } catch (_) {}
          mainTabEventController.add(4);
        });
        return true;
      },
    )..show(context: context);
  }

  void _loadNotices() async {
    final notices = await NoticeService.instance.fetchActiveNotices();
    if (mounted) {
      setState(() {
        _activeNotices = notices;
      });
    }
  }

  void _loadWeather() async {
    final weather = await WeatherService.fetchCurrentWeather();
    if (mounted && weather != null) {
      setState(() {
        _weatherInfo = weather;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.removeListener(_onGuideRequested);
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
      ApkUpdateService.instance.checkForUpdate().then((_) {
        if (mounted) setState(() {});
      });
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
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            toolbarHeight: 70,
            leadingWidth: padding + 40,
            leading: Padding(
              padding: EdgeInsets.only(left: padding),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const MyInfoPage()));
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Consumer<AuthService>(
                    key: _keyMyInfo,
                    builder: (context, auth, _) {
                      final photoUrl = auth.user?.photoURL;
                      if (photoUrl != null && photoUrl.isNotEmpty) {
                        return CircleAvatar(
                          radius: 20,
                          backgroundImage: NetworkImage(photoUrl),
                          backgroundColor: Colors.transparent,
                        );
                      }
                      return Icon(Icons.account_circle, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: 40);
                    },
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: padding),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NoticeListPage()),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Consumer<NoticeBadgeProvider>(
                      builder: (context, noticeBadge, child) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.notifications_none, color: Color(0xFFFFC700), size: 30),
                            if (noticeBadge.hasUnread)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF5252),
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 12,
                                    minHeight: 12,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
            centerTitle: true,
            title: SizedBox(
              height: titleFontSize + 40,
              child: Image.asset(
                'assets/title.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: ResponsiveBody(
                  fullWidthWhenExpanded: true,
                  child: _isLoading
                      ? Center(
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

                                          AnimatedRecentLogs(
                                            logs: statsProvider.recentDateLogs,
                                            isTablet: true,
                                          ),
                                          Expanded(
                                            child: _buildYoutubeSection(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return SingleChildScrollView(
                                child: Column(
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

                                    SizedBox(
                                      height: 220,
                                      child: _buildYoutubeSection(),
                                    ),
                                  ],
                                ),
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
            color: Theme.of(context).cardTheme.color!.withValues(alpha: 0.85),
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
                    : Theme.of(context).primaryColor,
                size: 22,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1.0),
                  child: Text(
                    noticeMsg,
                    style: TextStyle(
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _homeNoticeClosed = true;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
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

  void _handleClockIn(WorkTimerProvider provider) async {
    final currentWorkDate = WorkDateUtils.effectiveWorkDateYmd();
    final session = await DriveLogDatabase.instance.getDailyWorkSession(currentWorkDate);
    
    if (!mounted) return;

    if (session != null && (session['total_seconds'] ?? 0) > 0) {
      final result = await AppGlassDialog.show<String>(
        context: context,
        dialog: AppGlassDialog(
          icon: Icons.work_history_rounded,
          title: '출근 확인',
          content: '근무를 이어서 진행하시겠습니까?\n("아니요"를 누르면 초기화됩니다.)',
          actions: [
            GlassDialogCancelButton(label: '아니요', onPressed: () => Navigator.pop(context, 'reset')),
            GlassDialogConfirmButton(label: '예', filled: true, onPressed: () => Navigator.pop(context, 'continue')),
          ],
        ),
      );

      if (result == 'reset') {
        provider.clockIn(reset: true);
      } else if (result == 'continue') {
        provider.clockIn(reset: false);
      }
    } else {
      provider.clockIn(reset: false);
    }
  }

  void _handleClockOut(WorkTimerProvider provider) async {
    final confirm = await AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.logout_rounded,
        title: '퇴근 확인',
        content: '퇴근 처리하시겠습니까?\n기록은 자동으로 저장됩니다.',
        actions: [
          GlassDialogCancelButton(onPressed: () => Navigator.pop(context, false)),
          GlassDialogDestructiveButton(label: '퇴근하기', filled: true, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );

    if (confirm == true) {
      provider.clockOut();
    }
  }

  void _handleResetWorkTime(WorkTimerProvider provider) async {
    if (provider.elapsedSeconds == 0) return; // 이미 0이면 동작 안 함

    final confirm = await AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.refresh_rounded,
        title: '근무시간 초기화',
        content: '근무시간을 초기화 하시겠습니까?',
        actions: [
          GlassDialogCancelButton(onPressed: () => Navigator.pop(context, false)),
          GlassDialogDestructiveButton(label: '예', filled: true, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );

    if (confirm == true) {
      provider.resetWorkTimeForToday();
    }
  }

  Widget _buildSmallWorkTimerWidget() {
    return Consumer<WorkTimerProvider>(
      builder: (context, timerProvider, child) {
        final isClockedIn = timerProvider.isClockedIn;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: _keyWorkTimer,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: isClockedIn ? () {} : () => _handleClockIn(timerProvider),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isClockedIn ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.1) : const Color(0xFFFFC700),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('출근', style: TextStyle(color: isClockedIn ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.5) : Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: !isClockedIn ? () => _handleResetWorkTime(timerProvider) : () => _handleClockOut(timerProvider),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: !isClockedIn ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.1) : const Color(0xFFFF5252),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('퇴근', style: TextStyle(color: !isClockedIn ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.5) : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                timerProvider.formattedTime,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isClockedIn ? const Color(0xFFFFC700) : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.5),
                  letterSpacing: 1.0,
                  height: 1.1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTodaySummaryCard() {
    final statsProvider = Provider.of<TodayStatsProvider>(context);
    final DateTime workDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    final String dateFull = "${workDay.year}년 ${workDay.month}월 ${workDay.day}일 (${DateFormat('E', 'ko').format(workDay)})";

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color!,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTodayDailyList,
          splashColor: Theme.of(context).primaryColor.withValues(alpha: 0.12),
          highlightColor: Theme.of(context).dividerColor,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              dateFull,
                              style: TextStyle(
                                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_weatherInfo != null) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_weatherInfo!.message),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  '${_weatherInfo!.emoji} ${_weatherInfo!.temperature}°',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                      size: 14,
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: _buildSmallWorkTimerWidget(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '오늘 순익',
                          style: TextStyle(
                            color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              NumberFormat('#,###').format(statsProvider.todayNet),
                              style: TextStyle(
                                color: Color(0xFFFFC700),
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              '원',
                              style: TextStyle(
                                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '운행건수',
                              style: TextStyle(
                                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${statsProvider.todayLogs}건',
                              style: TextStyle(
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
                        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.1),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '지출',
                              style: TextStyle(
                                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${NumberFormat('#,###').format(statsProvider.todayExpenses)}원',
                              style: TextStyle(
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
          key: _keyWaitingFee,
          child: InkWell(
            onTap: () => WaitingFeeBottomSheet.show(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color!,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).primaryColor),
              ),
              alignment: Alignment.center,
              child: Row(
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
        SizedBox(width: 12),
        Expanded(
          key: _keyMap,
          child: InkWell(
            onTap: () {
              if (!kMapFeaturesEnabled) return;
              ProFeatureGuard.checkAndRun(
                context: context,
                featureKey: 'call_map',
                canUseFree: FeatureUsageService.canUseCallMapFree,
                canUseWithAd: FeatureUsageService.canUseCallMapWithAd,
                onGranted: (isFreeTicket) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CallPointMapPage()));
                },
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color!,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).primaryColor),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, color: Color(0xFFFFC700), size: 20),
                  SizedBox(width: 6),
                  Text('주변 콜맵', style: TextStyle(color: kMapFeaturesEnabled ? Theme.of(context).primaryColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
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
          key: _keySingleRegister,
          child: InkWell(
            onTap: () async {
              final canProceed = await ensureCallCardRecognitionDisclaimer(context, 'single');
              if (!canProceed) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SingleCallCardForm()));
              TodayStatsProvider.instance.refresh();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color!,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.credit_card, color: Color(0xFFFFC700), size: 32),
                  SizedBox(height: 10),
                  Text('콜카드 단건등록', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          key: _keyMultiRegister,
          child: InkWell(
            onTap: () async {
              final canProceed = await ensureCallCardRecognitionDisclaimer(context, 'multi');
              if (!canProceed) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiCallCardForm()));
              TodayStatsProvider.instance.refresh();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color!,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_add_check, color: Color(0xFFFFC700), size: 32),
                  SizedBox(height: 10),
                  Text('콜카드 다중등록', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontWeight: FontWeight.bold, fontSize: 15)),
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
      decoration: BorderedSection.decoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Theme.of(context).cardTheme.color!,
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
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: titleFs,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: isTablet ? 8 : 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final useVerticalLayout = constraints.maxHeight > 160;

                      Widget imageWidget = ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _latestYoutubeVideoId == null
                            ? Container(
                                color: Theme.of(context).cardTheme.color!,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.open_in_new,
                                      color: Color(0xFF9FA3AE),
                                      size: 28,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      YoutubeRssService.lastErrorMsg ?? '채널 방문하기',
                                      textAlign: TextAlign.center,
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
                                'https://i.ytimg.com/vi/$_latestYoutubeVideoId/0.jpg',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, _, _) => Container(
                                  color: Theme.of(context).cardTheme.color!,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.open_in_new,
                                        color: Color(0xFF9FA3AE),
                                        size: 28,
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        YoutubeRssService.lastErrorMsg ?? '썸네일 오류',
                                        textAlign: TextAlign.center,
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
                      );

                      Widget textWidget = _youtubeLoading
                          ? Align(
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
                                  _latestYoutubeChannelName.isEmpty &&
                                  _latestYoutubePublishedDot.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_latestYoutubeChannelName.isNotEmpty || _latestYoutubePublishedDot.isNotEmpty)
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
                                            if (_latestYoutubePublishedDot.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 6),
                                                child: Text(
                                                  _latestYoutubePublishedDot,
                                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                        color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                                                        fontSize: 10,
                                                        height: 1.2,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    if (_latestYoutubeTitle.isNotEmpty)
                                      Text(
                                        _latestYoutubeTitle,
                                        maxLines: useVerticalLayout ? 2 : 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                                              height: 1.3,
                                              fontSize: isTablet ? 14 : 12,
                                            ),
                                      ),
                                  ],
                                ));

                      if (useVerticalLayout) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: imageWidget),
                            SizedBox(height: 10),
                            textWidget,
                          ],
                        );
                      } else {
                        final thumbW = math.min(
                          isTablet ? 176.0 : 152.0,
                          constraints.maxWidth * (isTablet ? 0.42 : 0.38),
                        );
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: thumbW, child: imageWidget),
                            SizedBox(width: isTablet ? 12 : 10),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: textWidget,
                              ),
                            ),
                          ],
                        );
                      }
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
      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
      fontWeight: FontWeight.w700,
      fontSize: recentTitleFs,
      height: 1.12,
    );

    if (_recentLogs.isEmpty) {
      return Container(
        decoration: BorderedSection.decoration(context),
        padding: EdgeInsets.all(outerPadding),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '최근운행일지\n아직 등록된 운행일지가 없습니다.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
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
      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7),
      fontWeight: FontWeight.w500,
      height: 1.1,
      fontSize: bodyFs,
    );
    final routeTextStyle = TextStyle(
      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7),
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
      decoration: BorderedSection.decoration(context),
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
                                        SizedBox(width: 8),
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
                              SizedBox(width: 8),
                              Text(
                                '순익 ${NumberFormat('#,###').format(net)}',
                                style: moneyBaseStyle.copyWith(
                                  color: Theme.of(context).primaryColor,
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
                          onGranted: (isFreeTicket) {
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
                          color: Theme.of(context).cardTheme.color!,
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
                              color: Theme.of(context).primaryColor,
                              size: isTablet ? 26 : 22,
                            ),
                            SizedBox(height: isTablet ? 4 : 2),
                            Text(
                              '주변 콜맵',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
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
        color: Theme.of(context).cardTheme.color!,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all((textFs * 0.35).clamp(8.0, 12.0)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Theme.of(context).primaryColor, size: iconSz),
                SizedBox(height: (textFs * 0.25).clamp(4.0, 8.0)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: label.contains('\n') ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
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

class AnimatedRecentLogs extends StatefulWidget {
  final List<Map<String, dynamic>> logs;
  final bool isTablet;

  const AnimatedRecentLogs({
    Key? key,
    required this.logs,
    required this.isTablet,
  }) : super(key: key);

  @override
  State<AnimatedRecentLogs> createState() => _AnimatedRecentLogsState();
}

class _AnimatedRecentLogsState extends State<AnimatedRecentLogs> {
  late ScrollController _scrollController;
  Timer? _timer;
  final double _itemHeight = 44.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    if (widget.logs.isEmpty) return;
    final int visibleCount = 3;
    if (widget.logs.length <= visibleCount) return;

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_scrollController.hasClients) return;
      
      final currentScroll = _scrollController.offset;
      _scrollController.animateTo(
        currentScroll + _itemHeight,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnimatedRecentLogs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logs != widget.logs || oldWidget.isTablet != widget.isTablet) {
      _timer?.cancel();
      if (_scrollController.hasClients) {
         _scrollController.jumpTo(0);
      }
      _startAutoScroll();
    }
  }

  Color _getProgramColor(String program) {
    if (program.contains('카카오')) return const Color(0xFFFFC700);
    if (program.contains('로지')) return Colors.greenAccent;
    if (program.contains('콜마너')) return Colors.blueAccent;
    if (program.contains('아이콘')) return Colors.orangeAccent;
    if (program.contains('티맵')) return Colors.tealAccent;
    if (program.contains('대리')) return Colors.pinkAccent;
    return Colors.white70;
  }

  String _shortenProgramName(String program) {
    if (program.contains('카카오')) {
      if (program.contains('일반')) return '카(일)';
      if (program.contains('제휴')) return '카(제)';
      if (program.contains('맞춤')) return '카(맞)';
      if (program.contains('프리미엄') || program.contains('블랙')) return '카(프)';
      return '카카오';
    }
    if (program.contains('콜마너')) return '콜마';
    if (program.contains('핸들포유')) return '핸들';
    if (program.contains('로지')) return '로지';
    if (program.contains('아이콘')) return '아이콘';
    if (program.contains('티맵')) return '티맵';
    return program;
  }

  String _extractDong(String address) {
    if (address.trim().isEmpty) return '정보없음';
    final parts = address.trim().split(RegExp(r'\s+'));
    for (int i = parts.length - 1; i >= 0; i--) {
      final p = parts[i];
      if (p.endsWith('동') || p.endsWith('읍') || p.endsWith('면') || p.endsWith('구') || p.endsWith('리') || p.endsWith('로')) {
        return p;
      }
    }
    return parts.last;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.logs.isEmpty) {
      return const SizedBox.shrink();
    }

    final int visibleCount = 3;
    final double titleHeight = 30.0;
    final double paddingHeight = 24.0;
    final double containerHeight = titleHeight + paddingHeight + (_itemHeight * visibleCount);

    final bool isScrollable = widget.logs.length > visibleCount;
    final double titleFs = widget.isTablet ? 13.5 : 12.0;

    return Container(
      height: containerHeight,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BorderedSection.decoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '최근 운행일지',
                style: TextStyle(
                  fontFamily: 'GmarketSans',
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: titleFs,
                ),
              ),
              const SizedBox(width: 8),
              if (widget.logs.isNotEmpty)
                Text(
                  widget.logs.first['work_date']?.toString() ?? '',
                  style: TextStyle(
                    fontFamily: 'GmarketSans',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: titleFs - 2.0,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: isScrollable ? null : widget.logs.length,
              itemBuilder: (context, index) {
                final log = widget.logs[index % widget.logs.length];
                final programName = (log['program'] ?? '-').toString();
                final shortProgram = _shortenProgramName(programName);
                final start = (log['start_location'] ?? '').toString();
                final end = (log['end_location'] ?? '').toString();
                int fare = (log['gross_fare'] as int?) ?? 0;
                if (index % widget.logs.length == 0) fare = 150000;
                final driveTime = (log['drive_time'] ?? '').toString();

                final startDong = _extractDong(start);
                final endDong = _extractDong(end);
                final route = '$startDong -> $endDong';
                final double rowFontSize = ResponsiveLayout.summaryValueFontSize(context) * 0.85;

                return SizedBox(
                  height: _itemHeight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 42,
                          child: Text(
                            driveTime,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                              fontSize: rowFontSize,
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0),
                          width: 1,
                          height: 12,
                          color: Colors.white24,
                        ),
                        SizedBox(
                          width: 38,
                          child: Text(
                            shortProgram,
                            maxLines: 1,
                            textAlign: TextAlign.left,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _getProgramColor(programName),
                              fontWeight: FontWeight.bold,
                              fontSize: rowFontSize,
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0),
                          width: 1,
                          height: 12,
                          color: Colors.white24,
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  startDong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.white,
                                    fontSize: rowFontSize,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Icon(Icons.arrow_forward_rounded, size: 10, color: Colors.white38),
                              ),
                              Flexible(
                                child: Text(
                                  endDong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.white,
                                    fontSize: rowFontSize,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8.0),
                          width: 1,
                          height: 12,
                          color: Colors.white24,
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            NumberFormat('#,###').format(fare),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: rowFontSize,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

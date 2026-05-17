import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/feature_flags.dart';
import '../config/home_promo_config.dart';
import '../services/db_helper.dart';
import '../services/youtube_rss_service.dart';
import '../utils/work_date_utils.dart';
import 'log_list_page.dart';
import 'single_call_card_page.dart';
import 'multi_call_card_page.dart';
import '../expense_main_wrapper.dart';
import '../widgets/waiting_fee_bottom_sheet.dart';
import 'ocr_debug_page.dart';

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
    }
  }

  void requestLoadHomeData() {
    if (mounted) _loadHomeData();
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
    final stats = await DriveLogDatabase.instance.getTodayStatsByWorkDate(cal);
    final recent = await DriveLogDatabase.instance.getRecentLogs(limit: 5);

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 24.0 : 20.0;
    final titleFontSize = isTablet ? 20.0 : 18.0;
    final sectionGap = isTablet ? 12.0 : 10.0;

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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: const Color(0xFFFFC700),
                                fontWeight: FontWeight.bold,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
          : Padding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final outerPad = isTablet ? 22.0 : 16.0;
                  final innerW = constraints.maxWidth;
                  final availH = constraints.maxHeight - 2 * sectionGap;
                  final summarySectionH = availH * 34 / 100;
                  final innerCardW = innerW - 2 * outerPad;
                  final innerCardH = summarySectionH - 2 * outerPad;
                  final rowGap = (innerCardW * 0.022).clamp(8.0, 14.0);
                  final colGap = (innerCardW * 0.022).clamp(8.0, 14.0);
                  final cw = (innerCardW - colGap) / 2;
                  final ch = (innerCardH - rowGap) / 2;
                  final cell = cw < ch ? cw : ch;
                  final summaryValueFs = (cell * 0.20).clamp(26.0, 44.0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 34,
                        child: _buildTodaySummaryCard(summaryValueFontSize: summaryValueFs),
                      ),
                      SizedBox(height: sectionGap),
                      Expanded(
                        flex: 24,
                        child: _buildQuickActions(summaryValueFontSize: summaryValueFs),
                      ),
                      SizedBox(height: sectionGap),
                      Expanded(
                        flex: 18,
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
    );
  }

  Widget _buildTodaySummaryCard({required double summaryValueFontSize}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final outerPad = isTablet ? 22.0 : 16.0;

    final DateTime workDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    final String dateCompact = DateFormat('yyyy.MM.dd').format(workDay);
    final String weekdayLong = DateFormat('EEEE', 'ko').format(workDay);

    return Material(
      color: const Color(0xFF1F222A),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openTodayDailyList,
        splashColor: const Color(0xFFFFC700).withValues(alpha: 0.12),
        highlightColor: Colors.white10,
        child: Padding(
          padding: EdgeInsets.all(outerPad),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final rowGap = (w * 0.022).clamp(8.0, 14.0);
              final colGap = (w * 0.022).clamp(8.0, 14.0);
              final cw = (w - colGap) / 2;
              final ch = (h - rowGap) / 2;
              final cell = cw < ch ? cw : ch;

              final netFs = summaryValueFontSize;
              final titleTopInset = (cell * 0.06).clamp(8.0, 14.0);

              return Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16181D),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all((cell * 0.06).clamp(8.0, 14.0)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: titleTopInset),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        "오늘의 순수익",
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: netFs,
                                          height: 1.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_homeCalendarYmd.isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(top: (cell * 0.01).clamp(2.0, 6.0)),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '근무일 기준 · $_homeCalendarYmd',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: const Color(0xFF6E717C),
                                            fontSize: (netFs * 0.58).clamp(9.0, 12.0),
                                            fontWeight: FontWeight.w500,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  SizedBox(height: (cell * 0.04).clamp(6.0, 12.0)),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          "${NumberFormat('#,###').format(_todayNet)}원",
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFFFFC700),
                                            fontSize: netFs,
                                            height: 1.05,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: colGap),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF16181D),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all((cell * 0.06).clamp(8.0, 14.0)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: titleTopInset),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        dateCompact,
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: netFs,
                                          height: 1.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: (cell * 0.04).clamp(6.0, 12.0)),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          weekdayLong,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: netFs,
                                            height: 1.05,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: rowGap),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildMirrorSummaryCell(
                            icon: Icons.local_taxi,
                            label: "운행 건수",
                            value: "$_todayCount건",
                            valueColor: const Color(0xFFFFC700),
                            cell: cell,
                            netFs: netFs,
                          ),
                        ),
                        SizedBox(width: colGap),
                        Expanded(
                          child: _buildMirrorSummaryCell(
                            icon: Icons.payments_outlined,
                            label: "오늘 지출",
                            value: "${NumberFormat('#,###').format(_todayExpenses)}원",
                            valueColor: const Color(0xFFFF5252),
                            cell: cell,
                            netFs: netFs,
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
    );
  }

  Widget _buildMirrorSummaryCell({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    required double cell,
    required double netFs,
  }) {
    final iconSz = (cell * 0.22).clamp(26.0, 48.0);
    final box = iconSz + (iconSz * 0.20).clamp(14.0, 26.0);
    final pad = EdgeInsets.all((cell * 0.06).clamp(8.0, 14.0));
    final titleTopInset = (cell * 0.06).clamp(8.0, 14.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: titleTopInset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: netFs,
                      height: 1.12,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: (cell * 0.04).clamp(6.0, 12.0)),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: box,
                    height: box,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF121418),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(icon, color: const Color(0xFFFFC700), size: iconSz),
                      ),
                    ),
                  ),
                  SizedBox(width: (cell * 0.035).clamp(10.0, 16.0)),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: valueColor,
                            fontSize: netFs,
                            height: 1.05,
                            letterSpacing: -0.5,
                          ),
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
    );
  }

  Widget _buildQuickActions({required double summaryValueFontSize}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final outerPadding = isTablet ? 14.0 : 12.0;
    final spacing = isTablet ? 12.0 : 10.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(outerPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _quickActionButton(
                    Icons.credit_card,
                    "콜카드\n단건등록",
                    summaryValueFontSize,
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
                SizedBox(width: spacing),
                Expanded(
                  child: _quickActionButton(
                    Icons.credit_card,
                    "콜카드\n다중등록",
                    summaryValueFontSize,
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
          SizedBox(height: spacing),
          SizedBox(
            height: isTablet ? 44.0 : 40.0,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFC700),
                side: const BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => WaitingFeeBottomSheet.show(context),
              icon: const Icon(Icons.hourglass_bottom, size: 18),
              label: const Text(
                '대기비용 계산',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(height: spacing / 2),
          SizedBox(
            height: isTablet ? 36.0 : 32.0,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6E717C),
                side: const BorderSide(color: Color(0xFF3A3D46)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OcrDebugPage()),
              ),
              icon: const Icon(Icons.bug_report_outlined, size: 15),
              label: const Text(
                'OCR 디버그 (개발자용)',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYoutubeSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final outerPadding = isTablet ? 12.0 : 10.0;
    final titleFs = isTablet ? 13.5 : 12.0;

    return Material(
      color: const Color(0xFF1F222A),
      borderRadius: BorderRadius.circular(20),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: isTablet ? 176 : 152,
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
                ),
              ),
            ],
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final outerPadding = isTablet ? 14.0 : 12.0;
    final recentTitleFs = isTablet ? 20.0 : 17.0;
    final firstRowFs = isTablet ? 13.0 : 11.5;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: recentTitleFs,
        );

    if (_recentLogs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F222A),
          borderRadius: BorderRadius.circular(20),
        ),
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
    final metaTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w500,
          height: 1.1,
          fontSize: firstRowFs,
        );
    final routeTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w500,
          height: 1.1,
        );
    final moneyBaseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.1,
        );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openTodayDailyList,
          child: Padding(
            padding: EdgeInsets.all(outerPadding),
            child: Row(
              children: [
                Container(
                  width: isTablet ? 74 : 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16181D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.receipt_long, color: const Color(0xFFFFC700), size: isTablet ? 30 : 26),
                ),
                SizedBox(width: isTablet ? 12 : 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final rowCount = hasWaypoint ? 6 : 5;
                      final rowPad = EdgeInsets.symmetric(
                        vertical: (constraints.maxHeight * 0.01).clamp(1.0, 4.0),
                      );

                      Widget paddedRow(Widget child) {
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

                      final rows = <Widget>[
                        paddedRow(Text('최근운행일지', style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        paddedRow(
                          RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: metaTextStyle,
                              children: [
                                TextSpan(text: '$workDateLabel $time · '),
                                TextSpan(
                                  text: program,
                                  style: metaTextStyle?.copyWith(color: Colors.greenAccent),
                                ),
                              ],
                            ),
                          ),
                        ),
                        paddedRow(
                          Text(
                            start.isEmpty ? '출발지 : 정보 없음' : '출발지 : $start',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: routeTextStyle,
                          ),
                        ),
                        paddedRow(
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
                          paddedRow(
                            Text(
                              end.isEmpty ? '도착지 : 정보 없음' : '도착지 : $end',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: routeTextStyle,
                            ),
                          ),
                        paddedRow(
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '수입 ${NumberFormat('#,###').format(income)}원',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: moneyBaseStyle?.copyWith(color: Colors.lightBlueAccent),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '지출 ${NumberFormat('#,###').format(expense)}원',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: moneyBaseStyle?.copyWith(color: const Color(0xFFFF5252)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '순익 ${NumberFormat('#,###').format(net)}원',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.left,
                                      style: moneyBaseStyle?.copyWith(color: const Color(0xFFFFC700)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: rows.take(rowCount).toList(),
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

  Widget _quickActionButton(IconData icon, String label, double labelFontSize, VoidCallback onTap) {
    return SizedBox.expand(
      child: Material(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final m = math.min(w, h);
              final pad = (m * 0.06).clamp(8.0, 14.0);
              final gap = (h * 0.04).clamp(4.0, 8.0);
              final iconSize = (h * 0.30).clamp(26.0, 48.0);
              final labelSize = (labelFontSize * 0.56).clamp(12.0, 22.0);

              return Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: const Color(0xFFFFC700),
                      size: iconSize,
                    ),
                    SizedBox(height: gap),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: labelSize,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

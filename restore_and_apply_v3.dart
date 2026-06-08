import 'dart:io';
import 'dart:convert';

void main() async {
  final oldFile = File(r'C:\dbros_app\old_home_utf8.dart');
  var content = await oldFile.readAsString(encoding: utf8);
  content = content.replaceAll('\r\n', '\n');

  final startMarker = '  Widget _buildTodaySummaryCard() {';
  final endMarker = '  Widget _buildYoutubeSection() {';

  final startIdx = content.indexOf(startMarker);
  final endIdx = content.indexOf(endMarker);

  if (startIdx == -1 || endIdx == -1) {
    print('Markers not found in old_home_utf8.dart');
    exit(1);
  }

  final newMethodsCode = '''  Widget _buildTodaySummaryCard() {
    final statsProvider = Provider.of<TodayStatsProvider>(context);
    final DateTime workDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    final String dateFull = "\${workDay.year}년 \${workDay.month}월 \${workDay.day}일 (\${DateFormat('E', 'ko').format(workDay)})";

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
                              '\${statsProvider.todayLogs}건',
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
                              '\${NumberFormat('#,###').format(statsProvider.todayExpenses)}원',
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

''';

  content = content.substring(0, startIdx) + newMethodsCode + content.substring(endIdx);

  // Tablet Layout Replacement
  content = content.replaceAll(
'''                                          Expanded(
                                            flex: 11,
                                            child: _buildTodaySummaryCard(),
                                          ),
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
                                          ),''',
'''                                          _buildTodaySummaryCard(),
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
                                            height: 60,
                                            child: _buildRegisterRow(),
                                          ),
                                          SizedBox(height: sectionGap),
                                          Expanded(
                                            child: _buildYoutubeSection(),
                                          ),'''
  );

  // Portrait Layout Replacement
  content = content.replaceAll(
'''                              return Column(
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
                              );''',
'''                              return Column(
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
                                    height: 60,
                                    child: _buildRegisterRow(),
                                  ),
                                  SizedBox(height: sectionGap),
                                  Expanded(
                                    child: _buildYoutubeSection(),
                                  ),
                                ],
                              );'''
  );

  final outFile = File(r'C:\dbros_app\lib\screens\home_page.dart');
  await outFile.writeAsString(content, encoding: utf8);
  print('Successfully restored and applied all fixes.');
}

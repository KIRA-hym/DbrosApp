$content = Get-Content -Path "C:\dbros_app\lib\screens\home_page.dart" -Encoding UTF8 -Raw
$startIndex = $content.IndexOf("  Widget _buildTodaySummaryCard() {")
$endIndex = $content.IndexOf("  Widget _buildUtilsRow() {")
$newCode = @'
  Widget _buildTodaySummaryCard() {
    final statsProvider = Provider.of<TodayStatsProvider>(context);
    final DateTime workDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    final String dateFull = '${workDay.year}년 ${workDay.month}월 ${workDay.day}일 (${DateFormat('E', 'ko').format(workDay)})';

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
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateFull,
                      style: const TextStyle(
                        color: Color(0xFF9FA3AE),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Color(0xFF9FA3AE),
                      size: 14,
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      '오늘 순익',
                      style: TextStyle(
                        color: Color(0xFF9FA3AE),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                const Spacer(),
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
                                color: Color(0xFF9FA3AE),
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
                                color: Color(0xFF9FA3AE),
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

'@

if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
    $newFileContent = $content.Substring(0, $startIndex) + $newCode + $content.Substring($endIndex)
    Set-Content -Path "C:\dbros_app\lib\screens\home_page.dart" -Value $newFileContent -Encoding UTF8
    Write-Output "Successfully updated home_page.dart!"
} else {
    Write-Output "Failed to find markers."
}

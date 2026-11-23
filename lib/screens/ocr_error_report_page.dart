import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/ocr_parse_log_service.dart';

class OcrErrorReportPage extends StatefulWidget {
  const OcrErrorReportPage({super.key});

  /// 고객지원(이메일 문의)과 동일한 Google Apps Script 웹훅
  static const String reportWebhookUrl =
      'https://script.google.com/macros/s/AKfycbzPxzIGNuSzGLaiqIiTDBUm_9F2hqKKXveFo4_0ICJJ41qfQXwD5OB7H5xbsuFsUM-MDA/exec';

  static const String reportEmailTitle = '콜카드인식오류제보';

  /// 관리자에게 전송되는 메일 본문 포맷 생성 (단위 테스트 및 전송 공용)
  static String buildReportEmailContent({
    required String reporterEmail,
    required String deviceInfo,
    required String appVersion,
    required String reportedAt,
    required String capturedAt,
    required String program,
    required int grossFare,
    required String startLocation,
    required String waypoint,
    required String endLocation,
    required String parseError,
    required String rawText,
  }) {
    final sb = StringBuffer();
    sb.writeln('[제보자 기본정보]');
    sb.writeln('- 이메일: $reporterEmail');
    sb.writeln('- 기기정보: $deviceInfo');
    sb.writeln('- 앱 버전: $appVersion');
    sb.writeln('- 제보시각: $reportedAt');
    sb.writeln();
    sb.writeln('[콜카드 자동인식 결과]');
    sb.writeln('- 인식시각: ${capturedAt.isEmpty ? "(알 수 없음)" : capturedAt}');
    sb.writeln('- 프로그램: $program');
    sb.writeln(
      '- 총요금: ${grossFare == 0 ? "0원 (파싱실패 의심)" : "$grossFare원"}',
    );
    sb.writeln('- 출발지: ${startLocation.isEmpty ? "(없음)" : startLocation}');
    if (waypoint.isNotEmpty) {
      sb.writeln('- 경유지: $waypoint');
    }
    sb.writeln('- 도착지: ${endLocation.isEmpty ? "(없음)" : endLocation}');
    if (parseError.isNotEmpty) {
      sb.writeln('- 에러: $parseError');
    }
    sb.writeln();
    sb.writeln('[OCR 원본 텍스트 (RAW)]');
    sb.writeln(rawText.isEmpty ? '(원본 텍스트 없음)' : rawText);
    return sb.toString();
  }

  /// 저장된 로그 entry 목록을 화면 표시용 모델로 변환
  static List<OcrErrorReportItem> parseLogEntries(
    List<Map<String, dynamic>> logs,
  ) {
    final list = <OcrErrorReportItem>[];
    var idx = 1;
    for (final entry in logs.reversed) {
      final rawText = entry['raw_text']?.toString() ?? '';
      final recognized = entry['recognized'] as bool? ?? true;
      final program = entry['program']?.toString() ?? '';

      final parsed = entry['parsed_data'] as Map? ?? {};
      final rawFee = parsed['fee_amount'];
      final grossFare = rawFee is int
          ? rawFee
          : (rawFee is num ? rawFee.toInt() : 0);
      final startLocation = parsed['departure']?.toString() ?? '';
      final endLocation = parsed['destination']?.toString() ?? '';

      final waypoints = parsed['waypoints'] as List? ?? [];
      final waypoint = waypoints.isNotEmpty ? waypoints.first.toString() : '';

      final isFail =
          !recognized ||
          (startLocation.isEmpty && endLocation.isEmpty && grossFare == 0);

      final capturedAt = entry['captured_at']?.toString() ?? '';
      String timeStr = '';
      if (capturedAt.isNotEmpty) {
        final dt = DateTime.tryParse(capturedAt);
        if (dt != null) {
          timeStr =
              '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }
      }
      final statusStr = isFail ? '❌ 자동인식 실패' : '✅ 자동인식 성공';
      final displayName = timeStr.isNotEmpty
          ? '$timeStr ($statusStr)'
          : statusStr;

      final entryId = entry['id']?.toString().trim();
      final itemId = (entryId != null && entryId.isNotEmpty)
          ? entryId
          : '${capturedAt}_$idx';

      list.add(
        OcrErrorReportItem(
          id: itemId,
          imageIndex: idx++,
          imageName: displayName,
          program: program.isNotEmpty ? program : '❌ 인식불가',
          rawText: rawText,
          grossFare: grossFare,
          startLocation: startLocation,
          endLocation: endLocation,
          waypoint: waypoint,
          parseError: isFail ? '인식 실패 로그' : '',
          capturedAt: capturedAt,
        ),
      );
    }
    return list;
  }

  @override
  State<OcrErrorReportPage> createState() => _OcrErrorReportPageState();
}

class _OcrErrorReportPageState extends State<OcrErrorReportPage> {
  final List<OcrErrorReportItem> _results = [];
  final Set<String> _reportedIds = {};
  final Set<String> _submittingIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistoricalOcrLogs();
  }

  Future<void> _loadHistoricalOcrLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await OcrParseLogService.loadAllRecordedLogs();
      if (!mounted) return;
      if (logs.isNotEmpty) {
        setState(() {
          _results
            ..clear()
            ..addAll(OcrErrorReportPage.parseLogEntries(logs));
        });
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onTapReport(OcrErrorReportItem item) async {
    if (_reportedIds.contains(item.id) || _submittingIds.contains(item.id)) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            Theme.of(context).cardTheme.color ?? const Color(0xFF1C1F26),
        title: const Text(
          '콜카드 인식오류 제보',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '선택한 콜카드 인식정보를 관리자에게 전송합니다.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '취소',
              style: TextStyle(color: Color(0xFF9FA3AE)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '전송',
              style: TextStyle(
                color: Color(0xFFFFC700),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _submitErrorReport(item);
    }
  }

  Future<void> _submitErrorReport(OcrErrorReportItem item) async {
    setState(() => _submittingIds.add(item.id));

    try {
      String email = '이메일 없음';
      try {
        email = context.read<AuthService>().user?.email ?? '이메일 없음';
      } catch (_) {
        email = AuthService.instance.user?.email ?? '이메일 없음';
      }

      // 1. 앱 버전 및 기기 정보 수집 (고객지원 이메일 문의와 동일)
      String appVersion = '알 수 없음';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      } catch (_) {}

      String deviceInfo = '알 수 없는 기기';
      try {
        final deviceInfoPlugin = DeviceInfoPlugin();
        if (!kIsWeb && Platform.isAndroid) {
          final androidInfo = await deviceInfoPlugin.androidInfo;
          deviceInfo =
              'Android ${androidInfo.version.release} (${androidInfo.model})';
        } else if (!kIsWeb && Platform.isIOS) {
          final iosInfo = await deviceInfoPlugin.iosInfo;
          deviceInfo =
              'iOS ${iosInfo.systemVersion} (${iosInfo.utsname.machine})';
        }
      } catch (_) {}

      final now = DateTime.now();
      final reportedAt = now.toIso8601String().replaceFirst('T', ' ').substring(0, 19);

      final content = OcrErrorReportPage.buildReportEmailContent(
        reporterEmail: email,
        deviceInfo: deviceInfo,
        appVersion: appVersion,
        reportedAt: reportedAt,
        capturedAt: item.capturedAt,
        program: item.program,
        grossFare: item.grossFare,
        startLocation: item.startLocation,
        waypoint: item.waypoint,
        endLocation: item.endLocation,
        parseError: item.parseError,
        rawText: item.rawText,
      );

      // 2. 고객지원 이메일 문의와 동일한 GAS 웹훅으로 관리자 메일 직접 발송
      final payload = {
        'email': email,
        'title': OcrErrorReportPage.reportEmailTitle,
        'content': content,
        'deviceInfo': deviceInfo,
        'appVersion': appVersion,
      };

      final response = await http
          .post(
            Uri.parse(OcrErrorReportPage.reportWebhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 302) {
        if (!mounted) return;
        setState(() {
          _reportedIds.add(item.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('콜카드 인식오류 제보가 전송되었습니다.\n확인 후 빠르게 개선하겠습니다.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      } else {
        throw Exception('전송 실패 (상태 코드: ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('제보 전송에 실패했습니다: $e'),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingIds.remove(item.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121418),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '콜카드 인식오류 제보',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFFFC700),
              ),
            )
          : _results.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '저장된 콜카드 인식 기록이 없습니다.\n자동인식 사용 시 최근 기록이 여기에 표시됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final item = _results[i];
                return _ReportResultCard(
                  item: item,
                  isReported: _reportedIds.contains(item.id),
                  isSubmitting: _submittingIds.contains(item.id),
                  onReportTap: () => _onTapReport(item),
                );
              },
            ),
    );
  }
}

class _ReportResultCard extends StatefulWidget {
  final OcrErrorReportItem item;
  final bool isReported;
  final bool isSubmitting;
  final VoidCallback onReportTap;

  const _ReportResultCard({
    required this.item,
    required this.isReported,
    required this.isSubmitting,
    required this.onReportTap,
  });

  @override
  State<_ReportResultCard> createState() => _ReportResultCardState();
}

class _ReportResultCardState extends State<_ReportResultCard> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.item;
    final isUnrecognized = r.program.contains('인식불가');
    final hasFareIssue = r.grossFare == 0;
    final hasAddrIssue = r.startLocation.isEmpty || r.endLocation.isEmpty;
    final hasIssue =
        isUnrecognized ||
        hasFareIssue ||
        hasAddrIssue ||
        r.parseError.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasIssue
              ? const Color(0xFFFF5252).withValues(alpha: 0.5)
              : const Color(0xFF2E323C),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 (기존 콜카드 인식 로그와 동일)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isUnrecognized
                        ? const Color(0xFF3A1A1A)
                        : const Color(0xFF1A2A1A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.program,
                    style: TextStyle(
                      color: isUnrecognized
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF4CAF50),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '[${r.imageIndex}] ${r.imageName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9FA3AE),
                      fontSize: 11,
                    ),
                  ),
                ),
                if (hasIssue)
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF5252),
                    size: 16,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2E323C), height: 1),
          // 파싱 결과 (기존 콜카드 인식 로그와 동일)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  '💰 총요금',
                  r.grossFare == 0 ? '⚠️ 0원 (파싱실패 의심)' : '${r.grossFare}원',
                  warn: hasFareIssue,
                ),
                _infoRow(
                  '🚩 출발지',
                  r.startLocation.isEmpty ? '⚠️ 없음' : r.startLocation,
                  warn: r.startLocation.isEmpty,
                ),
                if (r.waypoint.isNotEmpty) _infoRow('🔄 경유지', r.waypoint),
                _infoRow(
                  '🏁 도착지',
                  r.endLocation.isEmpty ? '⚠️ 없음' : r.endLocation,
                  warn: r.endLocation.isEmpty,
                ),
                if (r.parseError.isNotEmpty)
                  _infoRow('❌ 에러', r.parseError, warn: true),
              ],
            ),
          ),
          // 하단 행: 좌측 RAW 텍스트 토글 + 우측 끝 제보등록 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _showRaw = !_showRaw),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showRaw ? Icons.expand_less : Icons.expand_more,
                            color: const Color(0xFF6E717C),
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _showRaw ? 'RAW 텍스트 숨기기' : 'RAW OCR 텍스트 보기',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6E717C),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildReportButton(),
              ],
            ),
          ),
          if (_showRaw)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121418),
                borderRadius: BorderRadius.circular(10),
              ),
              child: GestureDetector(
                onLongPress: () async {
                  await Clipboard.setData(ClipboardData(text: r.rawText));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('원본 텍스트가 클립보드에 복사되었습니다.'),
                      backgroundColor: Color(0xFF2A2D36),
                    ),
                  );
                },
                child: Text(
                  r.rawText,
                  style: const TextStyle(
                    color: Color(0xFFB0B5C0),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportButton() {
    if (widget.isSubmitting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFC700).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFFC700),
          ),
        ),
      );
    }

    if (widget.isReported) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.45),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF66BB6A), size: 14),
            SizedBox(width: 4),
            Text(
              '제보완료',
              style: TextStyle(
                color: Color(0xFF66BB6A),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton(
      onPressed: widget.onReportTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFFC700),
        foregroundColor: Colors.black,
        elevation: 0,
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text(
        '제보등록',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6E717C), fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: warn ? const Color(0xFFFF5252) : Colors.white,
                fontSize: 12,
                fontWeight: warn ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OcrErrorReportItem {
  final String id;
  final int imageIndex;
  final String imageName;
  final String program;
  final String rawText;
  final int grossFare;
  final String startLocation;
  final String endLocation;
  final String waypoint;
  final String parseError;
  final String capturedAt;

  const OcrErrorReportItem({
    required this.id,
    required this.imageIndex,
    required this.imageName,
    required this.program,
    required this.rawText,
    required this.grossFare,
    required this.startLocation,
    required this.endLocation,
    required this.waypoint,
    required this.parseError,
    required this.capturedAt,
  });
}

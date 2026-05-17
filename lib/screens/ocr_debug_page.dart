import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/logi_colmanner_ocr.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/tmap_trip_detail_ocr.dart';

class OcrDebugPage extends StatefulWidget {
  const OcrDebugPage({super.key});

  @override
  State<OcrDebugPage> createState() => _OcrDebugPageState();
}

class _OcrDebugPageState extends State<OcrDebugPage> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];
  final List<_OcrResult> _results = [];
  bool _isProcessing = false;
  int _processedCount = 0;

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    setState(() {
      _images.clear();
      _results.clear();
      _images.addAll(picked.map((x) => File(x.path)));
    });
    _processAll();
  }

  Future<void> _processAll() async {
    if (_images.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _results.clear();
    });

    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      for (int i = 0; i < _images.length; i++) {
        final file = _images[i];
        final input = InputImage.fromFilePath(file.path);
        final recognized = await recognizer.processImage(input);

        final List<TextBlock> blocks = List.from(recognized.blocks)
          ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
        final rawText = recognized.text;

        // 프로그램 감지
        final program = _detectProgram(blocks, rawText);

        // 파싱 결과
        String driveTime = '';
        int grossFare = 0;
        String startLoc = '';
        String endLoc = '';
        String waypoint = '';
        String parseError = '';

        try {
          if (program == '로지') {
            final full = blocks.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
            final p = LogiColmannerOcr.parseLogi(full, blocks: blocks);
            driveTime = p.driveTimeHm;
            grossFare = p.grossFare;
            startLoc = p.startLocation;
            endLoc = p.endLocation;
            waypoint = p.waypoint;
          } else if (program == '콜마너') {
            final full = blocks.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
            final p = LogiColmannerOcr.parseColmanner(full, blocks: blocks);
            driveTime = p.driveTimeHm;
            grossFare = p.grossFare;
            startLoc = p.startLocation;
            endLoc = p.endLocation;
            waypoint = p.waypoint;
          } else if (program != null && program.startsWith('카카오')) {
            final p = KakaoCallCardOcr.parseScreen(blocks, rawText);
            driveTime = p.driveTimeHm ?? '';
            grossFare = p.grossFare ?? 0;
            startLoc = p.startLocation;
            endLoc = p.endLocation;
            waypoint = p.waypoint;
          } else if (program == '카카오(커스텀)') {
            final p = KakaoCustomCallOcr.parseScreen(blocks, rawText);
            driveTime = p.driveTimeHm ?? '';
            grossFare = p.grossFare ?? 0;
            startLoc = p.startLocation;
            endLoc = p.endLocation;
          } else if (program == '티맵') {
            final p = TmapTripDetailOcr.tryParse(rawText, blocks: blocks);
            if (p != null) {
              driveTime = p.driveStartTimeHm;
              grossFare = p.grossFare;
              startLoc = p.startAddress;
              endLoc = p.endAddress;
            }
          }
        } catch (e) {
          parseError = e.toString();
        }

        final result = _OcrResult(
          imageIndex: i + 1,
          imageName: file.path.split(Platform.pathSeparator).last,
          program: program ?? '❌ 인식불가',
          rawText: rawText,
          driveTime: driveTime,
          grossFare: grossFare,
          startLocation: startLoc,
          endLocation: endLoc,
          waypoint: waypoint,
          parseError: parseError,
        );

        setState(() {
          _results.add(result);
          _processedCount = i + 1;
        });
      }
    } finally {
      await recognizer.close();
      setState(() => _isProcessing = false);
    }
  }

  String? _detectProgram(List<TextBlock> blocks, String fullText) {
    final normalized = fullText.replaceAll(RegExp(r'\s+'), '');
    for (final block in blocks) {
      if (block.text.contains('갱신')) return '로지';
      if (block.text.contains('출도')) return '콜마너';
    }
    if (normalized.contains('운행시작') && normalized.contains('출발지') && normalized.contains('도착지') &&
        (normalized.contains('입금액') || normalized.contains('고객과의거리'))) return '로지';
    if (normalized.contains('지사명') && normalized.contains('출도') &&
        normalized.contains('출발지') && normalized.contains('도착지')) return '콜마너';
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) return '티맵';
    if (KakaoCustomCallOcr.isCustomCallScreen(fullText)) return '카카오(커스텀)';
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) return KakaoCallCardOcr.refineProgramByAllianceHeuristic(fullText, blocks, kakao);
    for (final block in blocks) {
      if (block.text.contains('고객과 통화')) return '카카오(일반)';
    }
    return null;
  }

  String _buildLogText() {
    final sb = StringBuffer();
    sb.writeln('═══════════════════════════════════════');
    sb.writeln('  OCR 디버그 로그  |  총 ${_results.length}장');
    sb.writeln('  생성: ${DateTime.now().toString().substring(0, 19)}');
    sb.writeln('═══════════════════════════════════════');

    for (final r in _results) {
      sb.writeln();
      sb.writeln('▶ [${r.imageIndex}/${_results.length}] ${r.imageName}');
      sb.writeln('  프로그램: ${r.program}');
      sb.writeln('  ─ 파싱 결과 ─');
      sb.writeln('  운행시간: ${r.driveTime.isEmpty ? "(없음)" : r.driveTime}');
      sb.writeln('  총요금:   ${r.grossFare == 0 ? "(0원 = 파싱실패 의심)" : "${r.grossFare}원"}');
      sb.writeln('  출발지:   ${r.startLocation.isEmpty ? "(없음)" : r.startLocation}');
      sb.writeln('  경유지:   ${r.waypoint.isEmpty ? "(없음)" : r.waypoint}');
      sb.writeln('  도착지:   ${r.endLocation.isEmpty ? "(없음)" : r.endLocation}');
      if (r.parseError.isNotEmpty) {
        sb.writeln('  ⚠️ 파싱 에러: ${r.parseError}');
      }
      sb.writeln('  ─ RAW OCR 텍스트 ─');
      sb.writeln(r.rawText);
      sb.writeln('───────────────────────────────────────');
    }
    return sb.toString();
  }

  Future<void> _exportLog() async {
    if (_results.isEmpty) return;
    final logText = _buildLogText();
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/ocr_debug_$timestamp.txt');
    await file.writeAsString(logText, encoding: Utf8Codec());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      subject: 'OCR 디버그 로그',
    );
  }

  Future<void> _copyToClipboard() async {
    if (_results.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _buildLogText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사했습니다!'), backgroundColor: Color(0xFF2A2D36)),
    );
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
          'OCR 디버그',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_results.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy, color: Color(0xFFFFC700)),
              tooltip: '클립보드 복사',
              onPressed: _copyToClipboard,
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Color(0xFFFFC700)),
              tooltip: '파일로 공유',
              onPressed: _exportLog,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // 상단 경고 배너
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1A00),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFC700).withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bug_report, color: Color(0xFFFFC700), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '개발자 전용 도구 — OCR Raw 텍스트 및 파싱 결과를 추출합니다.\n이미지 선택 후 우측 상단 공유 버튼으로 로그를 전송하세요.',
                    style: TextStyle(color: Color(0xFFFFC700), fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 이미지 선택 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _pickImages,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.photo_library, size: 20),
                label: Text(
                  _isProcessing
                      ? 'OCR 스캔 중... ($_processedCount/${_images.length})'
                      : '콜카드 이미지 선택 (다중)',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC700),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0xFF6E5500),
                  disabledForegroundColor: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 결과 목록
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.document_scanner_outlined,
                            size: 64, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 16),
                        Text(
                          '이미지를 선택하면 OCR 스캔 결과가\n여기에 표시됩니다',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) => _ResultCard(result: _results[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatefulWidget {
  final _OcrResult result;
  const _ResultCard({required this.result});

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final isUnrecognized = r.program.contains('인식불가');
    final hasFareIssue = r.grossFare == 0;
    final hasAddrIssue = r.startLocation.isEmpty || r.endLocation.isEmpty;
    final hasIssue = isUnrecognized || hasFareIssue || hasAddrIssue || r.parseError.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasIssue ? const Color(0xFFFF5252).withValues(alpha: 0.5) : const Color(0xFF2E323C),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isUnrecognized
                        ? const Color(0xFF3A1A1A)
                        : const Color(0xFF1A2A1A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.program,
                    style: TextStyle(
                      color: isUnrecognized ? const Color(0xFFFF5252) : const Color(0xFF4CAF50),
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
                    style: const TextStyle(color: Color(0xFF9FA3AE), fontSize: 11),
                  ),
                ),
                if (hasIssue)
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 16),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2E323C), height: 1),
          // 파싱 결과
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('⏱ 운행시간', r.driveTime.isEmpty ? '⚠️ 없음' : r.driveTime,
                    warn: r.driveTime.isEmpty),
                _infoRow('💰 총요금', r.grossFare == 0 ? '⚠️ 0원 (파싱실패 의심)' : '${r.grossFare}원',
                    warn: hasFareIssue),
                _infoRow('🚩 출발지', r.startLocation.isEmpty ? '⚠️ 없음' : r.startLocation,
                    warn: r.startLocation.isEmpty),
                if (r.waypoint.isNotEmpty) _infoRow('🔄 경유지', r.waypoint),
                _infoRow('🏁 도착지', r.endLocation.isEmpty ? '⚠️ 없음' : r.endLocation,
                    warn: r.endLocation.isEmpty),
                if (r.parseError.isNotEmpty)
                  _infoRow('❌ 에러', r.parseError, warn: true),
              ],
            ),
          ),
          // RAW 텍스트 토글
          InkWell(
            onTap: () => setState(() => _showRaw = !_showRaw),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  Icon(
                    _showRaw ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF6E717C),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showRaw ? 'RAW 텍스트 숨기기' : 'RAW OCR 텍스트 보기',
                    style: const TextStyle(color: Color(0xFF6E717C), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_showRaw)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121418),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                r.rawText,
                style: const TextStyle(
                  color: Color(0xFFB0B5C0),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
        ],
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

class _OcrResult {
  final int imageIndex;
  final String imageName;
  final String program;
  final String rawText;
  final String driveTime;
  final int grossFare;
  final String startLocation;
  final String endLocation;
  final String waypoint;
  final String parseError;

  const _OcrResult({
    required this.imageIndex,
    required this.imageName,
    required this.program,
    required this.rawText,
    required this.driveTime,
    required this.grossFare,
    required this.startLocation,
    required this.endLocation,
    required this.waypoint,
    required this.parseError,
  });
}

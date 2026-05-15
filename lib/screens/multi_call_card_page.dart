import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import '../main_navigation.dart';
import '../services/db_helper.dart';
import '../services/image_storage_service.dart';
import '../services/settings_service.dart';
import '../services/ocr_parse_log_service.dart';
import '../utils/drive_time_format.dart';
import '../utils/logi_colmanner_ocr.dart';
import '../utils/work_date_utils.dart';
import '../utils/tmap_trip_detail_ocr.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/ocr_failure_feedback.dart';
import 'log_list_page.dart';
import '../widgets/drive_date_selector_bar.dart';

class MultiCallCardForm extends StatefulWidget {
  /// 운행일 `yyyy-MM-dd`. 미지정 시 당일.
  final String? driveDate;

  const MultiCallCardForm({super.key, this.driveDate});

  @override
  State<MultiCallCardForm> createState() => _MultiCallCardFormState();
}

class _MultiCallCardFormState extends State<MultiCallCardForm> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];
  final List<Map<String, dynamic>> _parsedLogs = [];
  bool _isSaving = false;
  int _programUnrecognizedCount = 0;
  final List<String> _failedOcrTexts = [];

  late DateTime _driveDay;

  @override
  void initState() {
    super.initState();
    final d = widget.driveDate;
    if (d != null && d.isNotEmpty) {
      try {
        final p = DateFormat('yyyy-MM-dd').parseStrict(d);
        _driveDay = DateTime(p.year, p.month, p.day);
      } catch (_) {
        _driveDay = WorkDateUtils.effectiveWorkDateStartOfDay();
      }
    } else {
      _driveDay = WorkDateUtils.effectiveWorkDateStartOfDay();
    }
  }

  String _driveDateStr() => DateFormat('yyyy-MM-dd').format(_driveDay);

  String _formatFailedOcrTexts() {
    if (_failedOcrTexts.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < _failedOcrTexts.length; i++) {
      if (i > 0) buffer.writeln();
      buffer.writeln('--- 이미지 ${i + 1} ---');
      buffer.write(_failedOcrTexts[i]);
    }
    return buffer.toString();
  }

  Future<void> _pickMultipleImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isEmpty) return;

      setState(() {
        _selectedImages.addAll(images.map((image) => File(image.path)));
        _parsedLogs.clear();
        _programUnrecognizedCount = 0;
        _failedOcrTexts.clear();
      });

      _showProcessingDialog();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("이미지 선택 중 오류가 발생했습니다: $e")),
      );
    }
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1F222A),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFC700)),
              const SizedBox(height: 16),
              const Text("콜카드를 분석 중입니다...", style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text("${_parsedLogs.length}/${_selectedImages.length}개 처리 완료", style: const TextStyle(color: Color(0xFF6E717C), fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    _processAllImages();
  }

  Future<void> _processAllImages() async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
    
    try {
      for (int i = 0; i < _selectedImages.length; i++) {
        final File imageFile = _selectedImages[i];
        
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

        final Map<String, dynamic> logData = await _parseImageToLog(recognizedText, imageFile);
        
        if (logData.isNotEmpty) {
          setState(() {
            _parsedLogs.add(logData);
          });
        } else {
          _programUnrecognizedCount++;
          _failedOcrTexts.add(recognizedText.text);
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("이미지 처리 중 오류: $e")),
      );
    } finally {
      await textRecognizer.close();
    }

    if (mounted) Navigator.pop(context);

    if (mounted) {
      final message = _programUnrecognizedCount > 0
          ? "${_parsedLogs.length}개의 운행일지가 파싱되었습니다. 등록 실패 ${_programUnrecognizedCount}건(사유: 프로그램 인식불가)"
          : "${_parsedLogs.length}개의 운행일지가 파싱되었습니다.";
      if (_programUnrecognizedCount > 0) {
        OcrFailureFeedback.showUnrecognizedSnackbar(
          context,
          message: message,
          fullText: _formatFailedOcrTexts(),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }

      _saveAllLogs();
    }
  }

  Future<Map<String, dynamic>> _parseImageToLog(RecognizedText recognizedText, File imageFile) async {
    List<TextBlock> blocks = List.from(recognizedText.blocks);
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rawProgram = _detectProgram(blocks, recognizedText.text);
    if (rawProgram == null) {
      OcrParseLogService.record(
        source: 'multi_call_card',
        rawText: recognizedText.text,
        parsedData: OcrParseLogService.parsedDataFrom(),
        recognized: false,
      );
      return {};
    }
    final detectedProgram = _normalizeProgramForSave(rawProgram);

    final Map<String, dynamic> logData = {
      'program': detectedProgram,
      'image_path': imageFile.path,
      'drive_date': _driveDateStr(),
      'drive_time': '',
      'gross_fare': 0,
      'transport_cost': 0,
      'start_location': '',
      'waypoint': '',
      'end_location': '',
      'memo': '',
    };

    if (rawProgram == KakaoCustomCallOcr.programCustom) {
      await _parseKakaoCustom(blocks, logData, fullText: recognizedText.text);
    } else if (rawProgram == KakaoCallCardOcr.programGeneral ||
        rawProgram == KakaoCallCardOcr.programPro ||
        rawProgram == KakaoCallCardOcr.programAlliance) {
      await _parseKakao(blocks, logData, fullText: recognizedText.text);
    } else if (rawProgram == "로지") {
      await _parseLogi(blocks, logData);
    } else if (rawProgram == "콜마너") {
      await _parseColmanner(blocks, logData);
    } else if (rawProgram == "티맵") {
      await _parseTmapTripDetail(recognizedText, logData);
    }

    final int grossFare = logData['gross_fare'] as int;
    final int transportCost = logData['transport_cost'] as int;
    final int fee = _calculateFee(detectedProgram, grossFare);
    final int netIncome = (grossFare - fee - transportCost).clamp(0, 999999999);

    logData['fee'] = fee;
    logData['net_income'] = netIncome;

    final ocrLogId = await OcrParseLogService.record(
      source: 'multi_call_card',
      program: detectedProgram,
      rawText: recognizedText.text,
      parsedData: OcrParseLogService.parsedDataFromLogData(logData),
    );
    if (ocrLogId != null) {
      logData['ocr_log_id'] = ocrLogId;
    }

    return logData;
  }

  String? _detectProgram(List<TextBlock> blocks, String fullText) {
    final normalized = fullText.replaceAll(RegExp(r'\s+'), '');
    for (final block in blocks) {
      if (block.text.contains("갱신")) return "로지";
      if (block.text.contains("출도")) return "콜마너";
    }
    if (normalized.contains('운행시작') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지') &&
        (normalized.contains('입금액') || normalized.contains('고객과의거리'))) {
      return "로지";
    }
    if (normalized.contains('지사명') &&
        normalized.contains('출도') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지')) {
      return "콜마너";
    }
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) return "티맵";
    if (KakaoCustomCallOcr.isCustomCallScreen(fullText)) return KakaoCustomCallOcr.programCustom;
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) {
      return KakaoCallCardOcr.refineProgramByAllianceHeuristic(fullText, blocks, kakao);
    }
    for (final block in blocks) {
      if (block.text.contains("고객과 통화")) {
        return KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          fullText,
          blocks,
          KakaoCallCardOcr.programGeneral,
        );
      }
    }
    return null;
  }

  String _normalizeProgramForSave(String program) {
    if (program == '카카오') return '카카오(일반)';
    if (program == KakaoCallCardOcr.programGeneral ||
        program == KakaoCallCardOcr.programPro ||
        program == KakaoCallCardOcr.programAlliance ||
        program == KakaoCustomCallOcr.programCustom) {
      return program;
    }
    return program;
  }

  Future<void> _parseKakaoCustom(List<TextBlock> blocks, Map<String, dynamic> logData, {required String fullText}) async {
    final p = KakaoCustomCallOcr.parseScreen(blocks, fullText);

    if (p.driveDateYmd != null) logData['drive_date'] = p.driveDateYmd;
    if (p.driveTimeHm != null) logData['drive_time'] = p.driveTimeHm;
    logData['waypoint'] = '';
    logData['start_location'] = p.startLocation;
    logData['end_location'] = p.endLocation;
    if (p.grossFare != null) logData['gross_fare'] = p.grossFare;
    if ((p.paymentMethod ?? '').isNotEmpty) {
      final prev = (logData['memo'] ?? '').toString().trim();
      final tag = '결제방식:${p.paymentMethod}';
      logData['memo'] = prev.isEmpty ? tag : '$tag $prev';
    }
  }

  Future<void> _parseKakao(List<TextBlock> blocks, Map<String, dynamic> logData, {required String fullText}) async {
    final p = KakaoCallCardOcr.parseScreen(blocks, fullText);

    if (p.driveDateYmd != null) logData['drive_date'] = p.driveDateYmd;
    if (p.driveTimeHm != null) logData['drive_time'] = p.driveTimeHm;
    logData['waypoint'] = p.waypoint;
    logData['start_location'] = p.startLocation;
    logData['end_location'] = p.endLocation;
    if (p.grossFare != null) logData['gross_fare'] = p.grossFare;
  }

  Future<void> _parseLogi(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    final sortedBlocks = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sortedBlocks.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseLogi(full, blocks: sortedBlocks);
    if (p.driveTimeHm.isNotEmpty) logData['drive_time'] = p.driveTimeHm;
    if (p.grossFare > 0) logData['gross_fare'] = p.grossFare;
    if (p.startLocation.isNotEmpty) logData['start_location'] = p.startLocation;
    if (p.endLocation.isNotEmpty) logData['end_location'] = p.endLocation;
    if (p.waypoint.isNotEmpty) logData['waypoint'] = p.waypoint;
  }

  Future<void> _parseColmanner(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sorted.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseColmanner(full, blocks: sorted);
    if (p.driveTimeHm.isNotEmpty) logData['drive_time'] = p.driveTimeHm;
    if (p.grossFare > 0) logData['gross_fare'] = p.grossFare;
    if (p.startLocation.isNotEmpty) logData['start_location'] = p.startLocation;
    if (p.endLocation.isNotEmpty) logData['end_location'] = p.endLocation;
    if (p.waypoint.isNotEmpty) logData['waypoint'] = p.waypoint;
  }

  Future<void> _parseTmapTripDetail(
    RecognizedText recognizedText,
    Map<String, dynamic> logData,
  ) async {
    final r = TmapTripDetailOcr.tryParse(
      recognizedText.text,
      blocks: recognizedText.blocks,
    );
    if (r == null) return;
    if (r.driveDateYmd.isNotEmpty) logData['drive_date'] = r.driveDateYmd;
    if (r.driveStartTimeHm.isNotEmpty) logData['drive_time'] = r.driveStartTimeHm;
    if (r.grossFare > 0) logData['gross_fare'] = r.grossFare;
    if (r.startAddress.isNotEmpty) logData['start_location'] = r.startAddress;
    if (r.endAddress.isNotEmpty) logData['end_location'] = r.endAddress;
  }

  int _calculateFee(String program, int grossFare) => SettingsService.deductionFeeFromGross(grossFare, program);

  /// 운행시간 미인식 건: 저장 직전 시각 기준으로 0, +30, +60… 분(목록 순서, 인식된 건은 건너뜀).
  void _applyFallbackDriveTimesForMulti(List<Map<String, dynamic>> logs) {
    final base = DateTime.now();
    var slot = 0;
    for (final logData in logs) {
      if (hasValidDriveTimeHm(logData['drive_time'])) continue;
      final t = base.add(Duration(minutes: 30 * slot));
      logData['drive_time'] = formatDriveTimeHm(t);
      slot++;
    }
  }

  Future<void> _saveAllLogs() async {
    if (_parsedLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("저장할 운행일지가 없습니다.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final String nowIso = DateTime.now().toIso8601String();
      int successCount = 0;

      final work = _driveDateStr();
      _applyFallbackDriveTimesForMulti(_parsedLogs);
      for (final logData in _parsedLogs) {
        final timeStr = resolveDriveTimeForStorage(logData['drive_time']?.toString());
        final drive = WorkDateUtils.resolveDriveDateForNightShift(work, timeStr);
        final imagePath = await ImageStorageService.compressAndPersistForDisplay(
          logData['image_path']?.toString(),
          prefix: 'multi',
        );
        final Map<String, dynamic> row = {
          "work_date": work,
          "drive_date": drive,
          "drive_time": timeStr,
          "program": logData['program'],
          "gross_fare": logData['gross_fare'],
          "fee": logData['fee'],
          "transport_cost": logData['transport_cost'],
          "net_income": logData['net_income'],
          "start_location": logData['start_location'],
          "waypoint": logData['waypoint'],
          "end_location": logData['end_location'],
          "memo": logData['memo'],
          "image_path": imagePath,
          "created_at": nowIso,
          "updated_at": nowIso,
        };

        final insertedId = await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
        final ocrLogId = logData['ocr_log_id']?.toString();
        if (ocrLogId != null && ocrLogId.isNotEmpty) {
          await OcrParseLogService.attachSavedDriveLog(
            ocrLogId,
            {...row, 'id': insertedId},
          );
        }
        successCount++;
      }

      if (!mounted) return;

      if (_parsedLogs.isNotEmpty) {
        final String workStr = _driveDateStr();
        final snack = "$successCount건의 운행일지가 등록되었습니다.";

        ScaffoldMessenger.of(context).clearSnackBars();
        MainTabScope.maybeOf(context)?.selectTab(1);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => DailyLogListPage(
              dateStr: workStr,
              dateTitle: '근무일자: $workStr',
              snackMessage: snack,
            ),
          ),
          (route) => route.isFirst,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$successCount건의 운행일지가 등록되었습니다.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 중 오류가 발생했습니다: $e")),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _clearAll() {
    setState(() {
      _selectedImages.clear();
      _parsedLogs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final titleFontSize = isTablet ? 20.0 : 18.0;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 12.0 : 10.0;
    final spacing = isTablet ? 24.0 : 20.0;

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        title: Text(
          "콜카드 다중등록",
          style: TextStyle(
            fontFamily: 'GmarketSans',
            fontWeight: FontWeight.w700,
            fontSize: titleFontSize,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white, size: isTablet ? 26 : 24),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_selectedImages.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_all, color: const Color(0xFFFFC700), size: isTablet ? 26 : 24),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("근무일자", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
            const SizedBox(height: 6),
            DriveDateSelectorBar(
              selectedDate: _driveDay,
              onDateChanged: (d) => setState(() => _driveDay = DateTime(d.year, d.month, d.day)),
            ),
            SizedBox(height: spacing),
            if (_selectedImages.isEmpty) ...[
              _buildEmptyState(),
            ] else ...[
              _buildImagePreview(),
              SizedBox(height: spacing),
              if (_isSaving) ...[
                _buildSavingState(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final iconSize = isTablet ? 100.0 : 80.0;
    final titleFontSize = isTablet ? 20.0 : 18.0;
    final subtitleFontSize = isTablet ? 16.0 : 14.0;
    final spacing = isTablet ? 24.0 : 20.0;
    final innerSpacing = isTablet ? 16.0 : 12.0;
    final buttonSpacing = isTablet ? 36.0 : 30.0;
    final horizontalPadding = isTablet ? 32.0 : 24.0;
    final verticalPadding = isTablet ? 16.0 : 12.0;
    final iconSizeButton = isTablet ? 24.0 : 20.0;

    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.credit_card,
              size: iconSize,
              color: const Color(0xFF6E717C),
            ),
            SizedBox(height: spacing),
            Text(
              "여러 개의 콜카드 이미지를 선택하세요",
              style: TextStyle(
                fontFamily: 'GmarketSans',
                fontSize: titleFontSize,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: innerSpacing),
            Text(
              "카카오, 로지, 콜마너, 티맵 콜카드를\n한 번에 처리할 수 있습니다",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF6E717C)),
            ),
            SizedBox(height: buttonSpacing),
            ElevatedButton.icon(
              onPressed: _pickMultipleImages,
              icon: Icon(Icons.photo_library, size: iconSizeButton),
              label: Text("콜카드 선택", style: TextStyle(fontSize: isTablet ? 16 : 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final containerHeight = isTablet ? 120.0 : 100.0;
    final itemWidth = isTablet ? 100.0 : 80.0;
    final itemMargin = isTablet ? 12.0 : 8.0;
    final borderRadius = isTablet ? 12.0 : 8.0;
    final borderWidth = isTablet ? 2.0 : 1.0;

    return Container(
      height: containerHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) {
          final File image = _selectedImages[index];
          return Container(
            width: itemWidth,
            margin: EdgeInsets.only(right: itemMargin),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: const Color(0xFFFFC700), width: borderWidth),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Image.file(
                image,
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSavingState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final titleFontSize = isTablet ? 18.0 : 16.0;
    final infoFontSize = isTablet ? 14.0 : 12.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final innerSpacing = isTablet ? 12.0 : 8.0;
    final indicatorSize = isTablet ? 48.0 : 40.0;

    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: indicatorSize,
              height: indicatorSize,
              child: const CircularProgressIndicator(color: Color(0xFFFFC700), strokeWidth: 4),
            ),
            SizedBox(height: spacing),
            Text(
              "저장 중...",
              style: TextStyle(color: Colors.white, fontSize: titleFontSize, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: innerSpacing),
            Text(
              "${_parsedLogs.length}건의 운행일지 처리 중",
              style: TextStyle(color: const Color(0xFF6E717C), fontSize: infoFontSize),
            ),
          ],
        ),
      ),
    );
  }
}

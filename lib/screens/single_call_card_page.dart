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
import '../services/gemini_api_service.dart';
import '../utils/drive_time_format.dart';
import '../utils/work_date_utils.dart';
import '../utils/tmap_trip_detail_ocr.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/ocr_failure_feedback.dart';
import 'log_list_page.dart';
import '../widgets/drive_date_selector_bar.dart';

class SingleCallCardForm extends StatefulWidget {
  /// 운행일 `yyyy-MM-dd`. 미지정 시 당일.
  final String? driveDate;

  const SingleCallCardForm({super.key, this.driveDate});

  @override
  State<SingleCallCardForm> createState() => _SingleCallCardFormState();
}

class _SingleCallCardFormState extends State<SingleCallCardForm> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isProcessing = false;
  bool _isSaving = false;
  String? _lastFailureReason;
  String _lastOcrFullText = '';

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

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() {
        _selectedImage = File(image.path);
      });

      _processImageAndSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("이미지 선택 중 오류가 발생했습니다: $e")),
      );
    }
  }

  Future<void> _processImageAndSave() async {
    if (_selectedImage == null) return;

    setState(() => _isProcessing = true);

    try {
      final inputImage = InputImage.fromFilePath(_selectedImage!.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final Map<String, dynamic> logData = await _parseImageToLog(recognizedText, _selectedImage!);
      
      if (logData.isNotEmpty) {
        await _saveLogData(logData);
      } else {
        if (!mounted) return;
        OcrFailureFeedback.showUnrecognizedSnackbar(
          context,
          message:
              "등록에 실패했습니다. 사유: ${_lastFailureReason ?? "콜카드 정보를 파싱할 수 없습니다."}",
          fullText: _lastOcrFullText,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("콜카드 처리 중 오류: $e")),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _parseImageToLog(RecognizedText recognizedText, File imageFile) async {
    List<TextBlock> blocks = List.from(recognizedText.blocks);
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rawProgram = _detectProgram(blocks, recognizedText.text);
    if (rawProgram == null) {
      _lastFailureReason = "프로그램 인식불가";
      _lastOcrFullText = recognizedText.text;
      OcrParseLogService.record(
        source: 'single_call_card',
        rawText: recognizedText.text,
        parsedData: OcrParseLogService.parsedDataFrom(),
        recognized: false,
      );
      return {};
    }
    _lastFailureReason = null;
    _lastOcrFullText = '';
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

    final r = await GeminiApiService.instance.parseCallCard(
      fullText: recognizedText.text,
      detectedProgram: rawProgram,
    );
    if (r.usageExceeded) {
      _lastFailureReason = '일일 콜카드인식건수 한도가 초과되었습니다.';
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('알림'),
            content: const Text('일일 콜카드인식건수 한도가 초과되었습니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
            ],
          ),
        );
      }
      return {};
    }
    if (r.fields == null) {
      _lastFailureReason = r.errorMessage ?? 'Gemini 파싱 실패';
      return {};
    }
    _fillLogDataFromGeminiFields(logData, r.fields!, recognizedText.text, rawProgram);

    final int grossFare = logData['gross_fare'] as int;
    final int transportCost = logData['transport_cost'] as int;
    final int fee = _calculateFee(detectedProgram, grossFare);
    final int netIncome = (grossFare - fee - transportCost).clamp(0, 999999999);

    logData['fee'] = fee;
    logData['net_income'] = netIncome;

    final ocrLogId = await OcrParseLogService.record(
      source: 'single_call_card',
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

  void _fillLogDataFromGeminiFields(
    Map<String, dynamic> logData,
    GeminiParsedFields f,
    String fullText,
    String rawProgram,
  ) {
    final dateM = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(fullText);
    if (dateM != null) {
      logData['drive_date'] =
          '${dateM.group(1)}-${dateM.group(2)!.padLeft(2, '0')}-${dateM.group(3)!.padLeft(2, '0')}';
    }
    logData['drive_time'] = f.driveTimeHm.isEmpty
        ? DateFormat('HH:mm').format(DateTime.now())
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    if (f.grossFare > 0) logData['gross_fare'] = f.grossFare;
    logData['start_location'] = f.startLocation;
    logData['end_location'] = f.endLocation;
    logData['waypoint'] = f.waypoint;
    if (rawProgram == KakaoCustomCallOcr.programCustom) {
      if (fullText.contains('카드')) {
        logData['memo'] = '결제방식:카드';
      } else if (fullText.contains('현금')) {
        logData['memo'] = '결제방식:현금';
      }
    }
  }

  int _calculateFee(String program, int grossFare) => SettingsService.deductionFeeFromGross(grossFare, program);

  Future<void> _saveLogData(Map<String, dynamic> logData) async {
    setState(() => _isSaving = true);

    try {
      final String nowIso = DateTime.now().toIso8601String();
      final work = _driveDateStr();
      final timeStr = resolveDriveTimeForStorage(logData['drive_time']?.toString());
      final drive = WorkDateUtils.resolveDriveDateForNightShift(work, timeStr);
      final imagePath = await ImageStorageService.compressAndPersistForDisplay(
        logData['image_path']?.toString(),
        prefix: 'single',
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

      if (!mounted) return;

      final String workStr = _driveDateStr();

      ScaffoldMessenger.of(context).clearSnackBars();
      MainTabScope.maybeOf(context)?.selectTab(1);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => DailyLogListPage(
            dateStr: workStr,
            dateTitle: '근무일자: $workStr',
            snackMessage: "운행일지가 등록되었습니다.",
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 중 오류가 발생했습니다: $e")),
      );
    } finally {
      setState(() => _isSaving = false);
    }
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
          "콜카드 단건등록",
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
            if (_selectedImage == null) ...[
              _buildEmptyState(),
            ] else ...[
              _buildImagePreview(),
              SizedBox(height: spacing),
              if (_isProcessing || _isSaving) ...[
                _buildProcessingState(),
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
              "콜카드 이미지를 선택하세요",
              style: TextStyle(
                fontFamily: 'GmarketSans',
                fontSize: titleFontSize,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: innerSpacing),
            Text(
              "카카오, 로지, 콜마너, 티맵 콜카드를\n선택하면 자동으로 등록됩니다",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: subtitleFontSize, color: const Color(0xFF6E717C)),
            ),
            SizedBox(height: buttonSpacing),
            ElevatedButton.icon(
              onPressed: _pickImage,
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
    final containerHeight = isTablet ? 240.0 : 200.0;
    final borderRadius = isTablet ? 20.0 : 16.0;
    final borderWidth = isTablet ? 3.0 : 2.0;
    final innerBorderRadius = borderRadius - borderWidth;

    return Container(
      height: containerHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFFFC700), width: borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerBorderRadius),
        child: Image.file(
          _selectedImage!,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildProcessingState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final titleFontSize = isTablet ? 18.0 : 16.0;
    final spacing = isTablet ? 24.0 : 16.0;
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
              _isSaving ? "저장 중..." : "콜카드 분석 중...",
              style: TextStyle(color: Colors.white, fontSize: titleFontSize, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

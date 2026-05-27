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
import '../services/call_card_ocr_parse_service.dart';
import '../utils/drive_time_format.dart';
import '../utils/work_date_utils.dart';
import '../utils/ocr_failure_feedback.dart';
import '../utils/app_image_picker.dart';
import 'log_list_page.dart';
import '../utils/responsive_layout.dart';
import '../widgets/drive_date_selector_bar.dart';
import '../widgets/responsive_body.dart';
import '../widgets/ad_banner_widget.dart';
import '../utils/pro_feature_guard.dart';
import '../services/feature_usage_service.dart';

class SingleCallCardForm extends StatefulWidget {
  /// 운행일 `yyyy-MM-dd`. 미지정 시 당일.
  final String? driveDate;

  const SingleCallCardForm({super.key, this.driveDate});

  @override
  State<SingleCallCardForm> createState() => _SingleCallCardFormState();
}

class _SingleCallCardFormState extends State<SingleCallCardForm> {
  File? _selectedImage;
  DateTime? _selectedImageDate;
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
    ProFeatureGuard.checkAndRun(
      context: context,
      featureKey: 'single_ocr',
      canUseFree: FeatureUsageService.canUseSingleOcrFree,
      canUseWithAd: FeatureUsageService.canUseSingleOcrWithAd,
      onGranted: () async {
        try {
          final result = await AppImagePicker.pickSingleGalleryImage(context);
          if (result == null) return;

          setState(() {
            _selectedImage = result.file;
            _selectedImageDate = result.creationDate;
          });

          _processImageAndSave(result.file, result.creationDate);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("이미지 선택 중 오류가 발생했습니다: $e")),
          );
        }
      },
    );
  }

  Future<void> _processImageAndSave(File imageFile, DateTime creationDate) async {
    if (_selectedImage == null) return;

    setState(() => _isProcessing = true);

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final Map<String, dynamic> logData = await CallCardOcrParseService.parseRecognizedText(
        recognizedText,
        imageFile,
        ocrSource: 'single_call_card',
      );
      
      if (logData.isEmpty) {
        _lastFailureReason = "프로그램 인식불가";
        _lastOcrFullText = recognizedText.text;
      }
      
      if (logData.isNotEmpty) {
        await _saveLogData(logData, imageFile, creationDate);
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

  Future<void> _saveLogData(Map<String, dynamic> logData, File imageFile, DateTime creationDate) async {
    setState(() => _isSaving = true);

    try {
      final String nowIso = DateTime.now().toIso8601String();
      // 이미지 파일의 원본 생성 시간을 운행 시간으로 사용 (OCR 파싱 시간 무시)
      final DateTime imageDate = creationDate;
      final work = WorkDateUtils.effectiveWorkDateYmd(imageDate);
      final timeStr = formatDriveTimeHm(imageDate);
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
            dateTitle: workStr,
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
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
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
      bottomNavigationBar: const AdBannerWidget(),
      body: ResponsiveBody(
        fullWidthWhenExpanded: true,
        maxWidth: ResponsiveLayout.formMaxWidth(MediaQuery.sizeOf(context)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isExpanded = ResponsiveLayout.isExpanded(context);
              final dateBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('근무일자', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
                  const SizedBox(height: 6),
                  DriveDateSelectorBar(
                    selectedDate: _driveDay,
                    onDateChanged: (d) => setState(() => _driveDay = DateTime(d.year, d.month, d.day)),
                  ),
                ],
              );

              if (!isExpanded) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateBlock,
                    SizedBox(height: spacing),
                    if (_selectedImage == null) ...[
                      _buildEmptyState(),
                    ] else ...[
                      _buildImagePreview(),
                      SizedBox(height: spacing),
                      if (_isProcessing || _isSaving) _buildProcessingState(),
                    ],
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dateBlock,
                  SizedBox(height: spacing),
                  Expanded(
                    child: _selectedImage == null
                        ? _buildEmptyState()
                        : (_isProcessing || _isSaving)
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 4, child: _buildProcessingState()),
                                  SizedBox(width: spacing),
                                  Expanded(flex: 6, child: _buildImagePreview(fillHeight: true)),
                                ],
                              )
                            : _buildImagePreview(fillHeight: true),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
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

  Widget _buildImagePreview({bool fillHeight = false}) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final borderRadius = isTablet ? 20.0 : 16.0;
    final borderWidth = isTablet ? 3.0 : 2.0;
    final innerBorderRadius = borderRadius - borderWidth;

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(innerBorderRadius),
      child: Image.file(
        _selectedImage!,
        fit: fillHeight ? BoxFit.contain : BoxFit.cover,
      ),
    );

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: const Color(0xFFFFC700), width: borderWidth),
    );

    if (fillHeight) {
      return Container(
        decoration: decoration,
        alignment: Alignment.center,
        child: image,
      );
    }

    final containerHeight = isTablet ? 240.0 : 200.0;
    return Container(
      height: containerHeight,
      decoration: decoration,
      child: image,
    );
  }

  Widget _buildProcessingState() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
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

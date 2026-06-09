import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import '../main_navigation.dart';
import '../services/call_card_ocr_parse_service.dart';
import '../utils/work_date_utils.dart';
import '../utils/work_date_utils.dart';
import '../utils/ocr_failure_feedback.dart';
import '../utils/app_image_picker.dart';
import 'log_list_page.dart';
import '../utils/responsive_layout.dart';
import '../widgets/drive_date_selector_bar.dart';
import '../widgets/responsive_body.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/app_empty_state.dart';
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
  Map<String, dynamic>? _parsedLog;
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
            _parsedLog = null;
            _isProcessing = true;
          });

          _processImageAndSave(result.file, result.creationDate);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("이미지 선택 중 오류가 발생했습니다: $e")));
        }
      },
    );
  }

  Future<void> _processImageAndSave(
    File imageFile,
    DateTime creationDate,
  ) async {
    if (_selectedImage == null) return;

    setState(() => _isProcessing = true);

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.korean,
      );
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      await textRecognizer.close();

      final Map<String, dynamic> logData =
          await CallCardOcrParseService.parseRecognizedText(
            recognizedText,
            imageFile,
            ocrSource: 'single_call_card',
          );

      if (logData.isEmpty) {
        _lastFailureReason = "프로그램 인식불가";
        _lastOcrFullText = recognizedText.text;
      }

      if (CallCardOcrParseService.isValidForAutoSave(logData)) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("콜카드 처리 중 오류: $e")));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveLogData(
    Map<String, dynamic> logData,
    File imageFile,
    DateTime creationDate,
  ) async {
    setState(() => _isSaving = true);

    try {
      final insertedId = await CallCardOcrParseService.saveLogToDatabase(
        logData,
        imagePrefix: 'single',
        originalDate: creationDate,
      );

      if (insertedId == null) {
        throw Exception("유효하지 않은 데이터이거나 이미 저장된(중복) 운행일지입니다.");
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("저장 중 오류가 발생했습니다: $e")));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 12.0 : 10.0;
    final spacing = isTablet ? 24.0 : 20.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "콜카드 단건등록",
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).primaryColor,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
            size: isTablet ? 26 : 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: const AdBannerWidget(),
      body: ResponsiveBody(
        fullWidthWhenExpanded: true,
        maxWidth: ResponsiveLayout.formMaxWidth(MediaQuery.sizeOf(context)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isExpanded = ResponsiveLayout.isExpanded(context);
              final dateBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '근무일자',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DriveDateSelectorBar(
                    selectedDate: _driveDay,
                    onDateChanged: (d) => setState(
                      () => _driveDay = DateTime(d.year, d.month, d.day),
                    ),
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
                      AppEmptyState(
                        icon: Icons.credit_card,
                        title: "콜카드 이미지를 선택하세요",
                        subtitle: "카카오, 로지, 콜마너, 티맵 콜카드를\n선택하면 자동으로 등록됩니다",
                        buttonText: "콜카드 선택",
                        buttonIcon: Icons.photo_library,
                        onButtonPressed: _pickImage,
                      ),
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
                        ? AppEmptyState(
                            icon: Icons.credit_card,
                            title: "콜카드 이미지를 선택하세요",
                            subtitle: "카카오, 로지, 콜마너, 티맵 콜카드를\n선택하면 자동으로 등록됩니다",
                            buttonText: "콜카드 선택",
                            buttonIcon: Icons.photo_library,
                            onButtonPressed: _pickImage,
                          )
                        : (_isProcessing || _isSaving)
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 4, child: _buildProcessingState()),
                              SizedBox(width: spacing),
                              Expanded(
                                flex: 6,
                                child: _buildImagePreview(fillHeight: true),
                              ),
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
      border: Border.all(color: Theme.of(context).primaryColor, width: borderWidth),
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
              child: const CircularProgressIndicator(
                color: Color(0xFFFFC700),
                strokeWidth: 4,
              ),
            ),
            SizedBox(height: spacing),
            Text(
              _isSaving ? "저장 중..." : "콜카드 분석 중...",
              style: TextStyle(
                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

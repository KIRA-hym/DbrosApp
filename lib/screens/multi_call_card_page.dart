import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import '../main_navigation.dart';
import '../services/call_card_ocr_parse_service.dart';
import '../utils/work_date_utils.dart';
import '../utils/ocr_failure_feedback.dart';
import 'log_list_page.dart';
import '../utils/responsive_layout.dart';
import '../utils/app_image_picker.dart';
import '../widgets/drive_date_selector_bar.dart';
import '../widgets/responsive_body.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/app_empty_state.dart';
import '../utils/pro_feature_guard.dart';
import '../services/feature_usage_service.dart';
import '../utils/call_card_recognition_disclaimer.dart';

class MultiCallCardForm extends StatefulWidget {
  /// 운행일 `yyyy-MM-dd`. 미지정 시 당일.
  final String? driveDate;

  const MultiCallCardForm({super.key, this.driveDate});

  @override
  State<MultiCallCardForm> createState() => _MultiCallCardFormState();
}

class _MultiCallCardFormState extends State<MultiCallCardForm> {
  final List<File> _selectedImages = [];
  final List<DateTime> _selectedImagesDates = [];
  final List<Map<String, dynamic>> _parsedLogs = [];
  // 파싱된 로그와 동일 순서로 원본 파일을 보관 (운행 시간 기준)
  final List<File> _parsedLogFiles = [];
  final List<DateTime> _parsedLogDates = [];
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
    final canProceed = await ensureCallCardRecognitionDisclaimer(context);
    if (!canProceed) return;

    ProFeatureGuard.checkAndRun(
      context: context,
      featureKey: 'multi_ocr',
      canUseFree: () async => false, // 1회차부터 광고
      canUseWithAd: FeatureUsageService.canUseMultiOcrWithAd,
      onGranted: () async {
        try {
          final results = await AppImagePicker.pickMultipleGalleryImages(
            context,
          );
          if (results.isEmpty) return;

          setState(() {
            _selectedImages.addAll(results.map((r) => r.file));
            _selectedImagesDates.addAll(results.map((r) => r.creationDate));
            _parsedLogs.clear();
            _parsedLogFiles.clear();
            _parsedLogDates.clear();
            _programUnrecognizedCount = 0;
            _failedOcrTexts.clear();
          });

          _showProcessingDialog();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("이미지 선택 중 오류가 발생했습니다: $e")));
        }
      },
    );
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).cardTheme.color!,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFC700)),
              const SizedBox(height: 16),
              Text(
                "콜카드를 분석 중입니다...",
                style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
              ),
              const SizedBox(height: 8),
              Text(
                "${_parsedLogs.length}/${_selectedImages.length}개 처리 완료",
                style: const TextStyle(color: Color(0xFF6E717C), fontSize: 12),
              ),
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
        final DateTime creationDate = _selectedImagesDates[i];

        final inputImage = InputImage.fromFilePath(imageFile.path);
        final RecognizedText recognizedText = await textRecognizer.processImage(
          inputImage,
        );

        final Map<String, dynamic> logData = await _parseImageToLog(
          recognizedText,
          imageFile,
        );

        if (CallCardOcrParseService.isValidForAutoSave(logData)) {
          setState(() {
            _parsedLogs.add(logData);
            _parsedLogFiles.add(imageFile);
            _parsedLogDates.add(creationDate);
          });
        } else {
          _programUnrecognizedCount++;
          _failedOcrTexts.add(recognizedText.text);
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("이미지 처리 중 오류: $e")));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }

      _saveAllLogs();
    }
  }

  Future<Map<String, dynamic>> _parseImageToLog(
    RecognizedText recognizedText,
    File imageFile,
  ) async {
    return CallCardOcrParseService.parseRecognizedText(
      recognizedText,
      imageFile,
      workDateYmd: _driveDateStr(),
      ocrSource: 'multi_call_card',
    );
  }

  Future<void> _saveAllLogs() async {
    if (_parsedLogs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("저장할 운행일지가 없습니다.")));
      return;
    }

    setState(() => _isSaving = true);

    try {
      int successCount = 0;

      for (int i = 0; i < _parsedLogs.length; i++) {
        final logData = _parsedLogs[i];
        // 이미지 파일의 원본 생성 시간을 운행 시간으로 사용 (OCR 파싱 시간 무시)
        final DateTime imageDate = (i < _parsedLogDates.length)
            ? _parsedLogDates[i]
            : DateTime.now();

        final insertedId = await CallCardOcrParseService.saveLogToDatabase(
          logData,
          imagePrefix: 'multi',
          originalDate: imageDate,
        );

        if (insertedId != null) {
          successCount++;
        }
      }

      if (!mounted) return;

      if (_parsedLogs.isNotEmpty) {
        final String workStr = _driveDateStr();
        bool hasAnyMissing = false;
        for (var log in _parsedLogs) {
          if (CallCardOcrParseService.getMissingFieldsList(log).isNotEmpty) {
            hasAnyMissing = true;
            break;
          }
        }
        
        final snack = hasAnyMissing 
            ? "$successCount건의 운행일지가 등록되었습니다. (자동인식 정보 누락 포함, 내역 확인 요망)"
            : "$successCount건의 운행일지가 등록되었습니다.";

        ScaffoldMessenger.of(context).clearSnackBars();
        MainTabScope.maybeOf(context)?.selectTab(1);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => DailyLogListPage(
              dateStr: workStr,
              dateTitle: workStr,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("저장 중 오류가 발생했습니다: $e")));
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
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 12.0 : 10.0;
    final spacing = isTablet ? 24.0 : 20.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "콜카드 다중등록",
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
        actions: [
          if (_selectedImages.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.clear_all,
                color: Theme.of(context).primaryColor,
                size: isTablet ? 26 : 24,
              ),
              onPressed: _clearAll,
            ),
        ],
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
                    if (_selectedImages.isEmpty) ...[
                      AppEmptyState(
                        icon: Icons.credit_card,
                        title: "여러 개의 콜카드 이미지를 선택하세요",
                        subtitle: "카카오, 로지, 콜마너, 티맵 콜카드를\n한 번에 처리할 수 있습니다",
                        buttonText: "콜카드 선택",
                        buttonIcon: Icons.photo_library,
                        onButtonPressed: _pickMultipleImages,
                      ),
                    ] else ...[
                      _buildImagePreview(),
                      SizedBox(height: spacing),
                      if (_isSaving) _buildSavingState(),
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
                    child: _selectedImages.isEmpty
                        ? AppEmptyState(
                            icon: Icons.credit_card,
                            title: "여러 개의 콜카드 이미지를 선택하세요",
                            subtitle: "카카오, 로지, 콜마너, 티맵 콜카드를\n한 번에 처리할 수 있습니다",
                            buttonText: "콜카드 선택",
                            buttonIcon: Icons.photo_library,
                            onButtonPressed: _pickMultipleImages,
                          )
                        : _isSaving
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 4, child: _buildSavingState()),
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
    final containerHeight = fillHeight ? null : (isTablet ? 120.0 : 100.0);
    final itemWidth = fillHeight ? null : (isTablet ? 100.0 : 80.0);
    final itemMargin = isTablet ? 12.0 : 8.0;
    final borderRadius = isTablet ? 12.0 : 8.0;
    final borderWidth = isTablet ? 2.0 : 1.0;

    Widget thumb(File image, {double? width, double? height}) {
      return Container(
        width: width,
        height: height,
        margin: EdgeInsets.only(
          right: itemMargin,
          bottom: fillHeight ? itemMargin : 0,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Theme.of(context).primaryColor,
            width: borderWidth,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.file(image, fit: BoxFit.cover),
        ),
      );
    }

    if (fillHeight) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final thumbH = (constraints.maxHeight - itemMargin).clamp(
            80.0,
            200.0,
          );
          final thumbW = thumbH * 0.75;
          return SingleChildScrollView(
            child: Wrap(
              spacing: itemMargin,
              runSpacing: itemMargin,
              children: [
                for (final image in _selectedImages)
                  thumb(image, width: thumbW, height: thumbH),
              ],
            ),
          );
        },
      );
    }

    return SizedBox(
      height: containerHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        itemBuilder: (context, index) => thumb(
          _selectedImages[index],
          width: itemWidth,
          height: containerHeight,
        ),
      ),
    );
  }

  Widget _buildSavingState() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
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
              child: const CircularProgressIndicator(
                color: Color(0xFFFFC700),
                strokeWidth: 4,
              ),
            ),
            SizedBox(height: spacing),
            Text(
              "저장 중...",
              style: TextStyle(
                color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: innerSpacing),
            Text(
              "${_parsedLogs.length}건의 운행일지 처리 중",
              style: TextStyle(
                color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                fontSize: infoFontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import '../main_navigation.dart';
import '../services/db_helper.dart';
import '../services/settings_service.dart';
import '../utils/drive_time_format.dart';
import '../utils/logi_fare_parse.dart';
import '../utils/work_date_utils.dart';
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

  Future<void> _pickMultipleImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isEmpty) return;

      setState(() {
        _selectedImages.addAll(images.map((image) => File(image.path)));
        _parsedLogs.clear();
        _programUnrecognizedCount = 0;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      
      _saveAllLogs();
    }
  }

  Future<Map<String, dynamic>> _parseImageToLog(RecognizedText recognizedText, File imageFile) async {
    List<TextBlock> blocks = List.from(recognizedText.blocks);
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final detectedProgram = _detectProgram(blocks);
    if (detectedProgram == null) return {};

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

    if (detectedProgram == "카카오") {
      await _parseKakao(blocks, logData);
    } else if (detectedProgram == "로지") {
      await _parseLogi(blocks, logData);
    } else if (detectedProgram == "콜마너") {
      await _parseColmanner(blocks, logData);
    }

    final int grossFare = logData['gross_fare'] as int;
    final int transportCost = logData['transport_cost'] as int;
    final int fee = _calculateFee(detectedProgram, grossFare);
    final int netIncome = (grossFare - fee - transportCost).clamp(0, 999999999);

    logData['fee'] = fee;
    logData['net_income'] = netIncome;

    return logData;
  }

  String? _detectProgram(List<TextBlock> blocks) {
    for (final block in blocks) {
      if (block.text.contains("고객과 통화")) return "카카오";
      if (block.text.contains("갱신")) return "로지";
      if (block.text.contains("출도")) return "콜마너";
    }
    return null;
  }

  Future<void> _parseKakao(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    String? parsedDate;
    String? parsedTime;
    String parsedWaypoint = "";
    final StringBuffer startLocBuffer = StringBuffer();
    final StringBuffer endLocBuffer = StringBuffer();
    int? parsedIncome;

    for (var block in blocks) {
      final double y = block.boundingBox.top;
      final String text = block.text.trim();
      
      if (y < 200) {
        final dateMatch = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(text);
        if (dateMatch != null) {
          parsedDate = "${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}";
        }
        final timeMatch = RegExp(r'\d{1,2}:\d{1,2}').firstMatch(text);
        if (timeMatch != null) {
          parsedTime = normalizeDriveTimeHm(timeMatch.group(0)!) ?? timeMatch.group(0)!;
        }
      }
      
      if (text.contains("경유")) {
        parsedWaypoint = text.replaceAll("경유", "").trim();
        continue;
      }
      
      if (y > 500 && y < 900 && !text.contains(RegExp(r'배정|메뉴|완료|취소'))) {
        startLocBuffer.write("$text ");
      }
      
      if (y > 900 && y < 1400) {
        endLocBuffer.write("$text ");
      }
      
      if (y > 1400 && text.contains(RegExp(r'\d{3,}'))) {
        final String cleanNum = text.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanNum.length >= 4) {
          parsedIncome = int.parse(cleanNum);
        }
      }
    }

    if (parsedDate != null) logData['drive_date'] = parsedDate;
    if (parsedTime != null) logData['drive_time'] = parsedTime;
    logData['waypoint'] = parsedWaypoint;
    logData['start_location'] = startLocBuffer.toString().trim();
    logData['end_location'] = endLocBuffer.toString().trim();
    if (parsedIncome != null) logData['gross_fare'] = parsedIncome;
  }

  Future<void> _parseLogi(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    final noiseList = ['완료', '배차', '경로', '지도', '처리', '취소', '안내', '닫기', '서명', '갱신', '고객ID', '오더번호', '차량번호', '출도', '전화', '전화2', '적요', '메모', '법인', '고객', '도착', '연기', '상황실', '발주사', '이용개시번호', '통화'];
    final labelList = ['도착지', '출발지', '요금', '입금액'];
    final List<TextBlock> sortedBlocks = List.from(blocks)..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    
    bool startParsed = false;
    bool endParsed = false;
    String parsedTime = "";
    String parsedIncome = "";
    String parsedStart = "";
    String parsedEnd = "";

    for (int i = 0; i < sortedBlocks.length; i++) {
      final String text = sortedBlocks[i].text.trim();
      final String norm = text.replaceAll('그', '7').replaceAll('l', '1').replaceAll('o', '0');

      if (sortedBlocks[i].boundingBox.top < 200 && parsedTime.isEmpty) {
        final tMatch = RegExp(r'(\d{1,2}:\d{1,2})').firstMatch(norm);
        if (tMatch != null) {
          parsedTime = normalizeDriveTimeHm(tMatch.group(1)!) ?? tMatch.group(1)!;
        }
      }

      if (text.contains("요금")) {
        int? n = parseLogiFareFromOcrText(text);
        if (n == null) {
          for (final j in [i - 1, i + 1]) {
            if (j >= 0 && j < sortedBlocks.length) {
              n = parseLogiFareFromOcrText(sortedBlocks[j].text);
              if (n != null) break;
            }
          }
        }
        if (n != null) parsedIncome = n.toString();
      }

      if (text == "출발지" && !startParsed) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sortedBlocks.length) {
            final String neighbor = sortedBlocks[j].text.trim();
            if (!noiseList.contains(neighbor) && !labelList.contains(neighbor) && neighbor.length > 5) {
              addr += (addr.isEmpty ? "" : " ") + neighbor;
            }
          }
        }
        if (addr.isNotEmpty && !addr.contains("도착")) {
          parsedStart = addr.replaceAll("상세:", "").trim();
          startParsed = true;
        }
      }

      if (text == "도착지" && !endParsed) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sortedBlocks.length) {
            final String neighbor = sortedBlocks[j].text.trim();
            if (!noiseList.contains(neighbor) && !labelList.contains(neighbor) && neighbor.length > 3) {
              addr += (addr.isEmpty ? "" : " ") + neighbor;
            }
          }
        }
        if (addr.isNotEmpty) {
          parsedEnd = addr.trim();
          endParsed = true;
        }
      }
    }

    if (parsedTime.isNotEmpty) logData['drive_time'] = parsedTime;
    if (parsedIncome.isNotEmpty) logData['gross_fare'] = int.parse(parsedIncome);
    if (parsedStart.isNotEmpty) logData['start_location'] = parsedStart;
    if (parsedEnd.isNotEmpty) logData['end_location'] = parsedEnd;
  }

  Future<void> _parseColmanner(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    final List<TextBlock> sorted = List.from(blocks)..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final noiseList = ['완료', '배차', '경로', '지도', '처리', '취소', '안내', '닫기', '서명', '갱신', '오더번호', '출도', '전화', '적요', '메모', '법인', '고객', '도착', '연기', '상황실', '발주사', '이용개시번호', '통화', '합계', '수수료', '보험료', '차감합계', '입금합계', '예상', '고객위치', '길안내', '운행'];
    
    String parsedTime = "";
    String parsedIncome = "";
    String parsedStart = "";
    String parsedEnd = "";

    for (int i = 0; i < sorted.length; i++) {
      final String text = sorted[i].text.trim();
      final String cleanText = text.replaceAll(RegExp(r'\s+'), '').replaceAll('그', '7').replaceAll('l', '1').replaceAll('o', '0');
      final double y = sorted[i].boundingBox.top;

      if (y < 250 && parsedTime.isEmpty) {
        final tMatch = RegExp(r'(\d{1,2}[:：\.]\d{1,2})').firstMatch(cleanText);
        if (tMatch != null) {
          final ts = tMatch.group(1)!.replaceAll('.', ':').replaceAll('：', ':');
          parsedTime = normalizeDriveTimeHm(ts) ?? ts;
        }
      }

      if (cleanText.contains("요금")) {
        final matches = RegExp(r'\d{4,6}').allMatches(cleanText.replaceAll(',', ''));
        if (matches.isNotEmpty) {
          final List<int> prices = matches.map((m) => int.parse(m.group(0)!)).toList()..sort((a, b) => b.compareTo(a));
          if (prices.isNotEmpty) parsedIncome = prices.first.toString();
        }
      }

      if (text.contains("출발지")) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sorted.length) {
            final String n = sorted[j].text.trim();
            if (!noiseList.contains(n) && n.length > 3 && !n.contains("도착")) {
              addr += (addr.isEmpty ? "" : " ") + n;
            }
          }
        }
        if (addr.isNotEmpty) parsedStart = addr.replaceAll("상세:", "").trim();
      }

      if (text.contains("도착지")) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sorted.length) {
            final String n = sorted[j].text.trim();
            if (!noiseList.contains(n) && n.length > 3) {
              addr += (addr.isEmpty ? "" : " ") + n;
            }
          }
        }
        if (addr.isNotEmpty) parsedEnd = addr.trim();
      }
    }

    if (parsedTime.isNotEmpty) logData['drive_time'] = parsedTime;
    if (parsedIncome.isNotEmpty) logData['gross_fare'] = int.parse(parsedIncome);
    if (parsedStart.isNotEmpty) logData['start_location'] = parsedStart;
    if (parsedEnd.isNotEmpty) logData['end_location'] = parsedEnd;
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
          "image_path": logData['image_path'],
          "created_at": nowIso,
          "updated_at": nowIso,
        };

        await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
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
              "카카오, 로지, 콜마너 콜카드를\n한 번에 처리할 수 있습니다",
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

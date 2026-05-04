import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import '../main_navigation.dart';
import '../services/db_helper.dart';
import '../services/image_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/drive_time_format.dart';
import '../utils/logi_fare_parse.dart';
import '../utils/work_date_utils.dart';
import '../utils/tmap_trip_detail_ocr.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("등록에 실패했습니다. 사유: ${_lastFailureReason ?? "콜카드 정보를 파싱할 수 없습니다."}")),
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
      return {};
    }
    _lastFailureReason = null;
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
    } else if (rawProgram == KakaoCallCardOcr.programGeneral || rawProgram == KakaoCallCardOcr.programPro) {
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

    return logData;
  }

  String? _detectProgram(List<TextBlock> blocks, String fullText) {
    for (final block in blocks) {
      if (block.text.contains("갱신")) return "로지";
      if (block.text.contains("출도")) return "콜마너";
    }
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) return "티맵";
    if (KakaoCustomCallOcr.isCustomCallScreen(fullText)) return KakaoCustomCallOcr.programCustom;
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) return kakao;
    for (final block in blocks) {
      if (block.text.contains("고객과 통화")) return KakaoCallCardOcr.programGeneral;
    }
    return null;
  }

  String _normalizeProgramForSave(String program) {
    if (program == '카카오') return '카카오(일반)';
    if (program == KakaoCallCardOcr.programGeneral ||
        program == KakaoCallCardOcr.programPro ||
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

      await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);

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

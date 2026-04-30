import 'dart:async';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/db_helper.dart';
import '../services/settings_service.dart';
import '../services/today_stats_notification_service.dart';
import '../main_navigation.dart';
import '../utils/drive_time_format.dart';
import '../utils/logi_fare_parse.dart';
import '../utils/work_date_utils.dart';
import '../utils/address_normalize.dart';
import 'location_pick_map_page.dart';
import 'log_list_page.dart';

class DriveLogForm extends StatefulWidget {
  final Map<String, dynamic>? existingLog;
  final String? initialDate;
  /// 알림 퀵등록 등: 반투명 배경 위 카드 형태 간소 표시
  final bool quickPanel;
  /// 시스템 오버레이로 띄운 경우(다른 앱 위 레이어). 저장 후 리스트 네비 대신 오버레이 종료.
  final bool fromOverlay;
  const DriveLogForm({
    super.key,
    this.existingLog,
    this.initialDate,
    this.quickPanel = false,
    this.fromOverlay = false,
  });

  @override
  State<DriveLogForm> createState() => _DriveLogFormState();
}

class _DriveLogFormState extends State<DriveLogForm> with WidgetsBindingObserver {
  final _workDateCon = TextEditingController();
  final _dateCon = TextEditingController();
  final _timeCon = TextEditingController();
  final _incomeCon = TextEditingController();
  final _transportCon = TextEditingController();
  final _waypointTipCon = TextEditingController();
  final _startLocCon = TextEditingController();
  final _waypointCon = TextEditingController();
  final _endLocCon = TextEditingController();
  final _memoCon = TextEditingController();

  int? _logId;
  int _grossIncome = 0;
  String _deductionHint = "";
  String _selectedProgram = SettingsService.programList.isNotEmpty ? SettingsService.programList.first : "카카오";
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _showWaypointField = false;

  bool _manualWorkDateRoll = false;
  String? _syncedEffectiveYmd;
  Timer? _workDateRollTimer;
  bool _autoWorkDateRollActive = false;
  bool _overlayAutoOcrHandled = false;

  double? _startLat;
  double? _startLng;
  double? _endLat;
  double? _endLng;

  @override
  void initState() {
    super.initState();
    if (widget.existingLog != null) {
      final log = widget.existingLog!;
      _logId = log['id'];
      _workDateCon.text = (log['work_date'] ?? log['drive_date'])?.toString() ?? '';
      _dateCon.text = log['drive_date']?.toString() ?? '';
      _timeCon.text = normalizeDriveTimeHm(log['drive_time']?.toString()) ?? log['drive_time']?.toString() ?? '';
      _selectedProgram = log['program'];
      _incomeCon.text = NumberFormat('#,###').format(log['gross_fare']);
      _transportCon.text = log['transport_cost'] > 0 ? NumberFormat('#,###').format(log['transport_cost']) : '';
      _waypointTipCon.text = log['waypoint_tip'] != null && log['waypoint_tip'] > 0 ? NumberFormat('#,###').format(log['waypoint_tip']) : '';
      _startLocCon.text = log['start_location'] ?? '';
      _waypointCon.text = log['waypoint'] ?? '';
      _endLocCon.text = log['end_location'] ?? '';
      _memoCon.text = log['memo'] ?? '';
      _startLat = (log['start_lat'] as num?)?.toDouble();
      _startLng = (log['start_lng'] as num?)?.toDouble();
      _endLat = (log['end_lat'] as num?)?.toDouble();
      _endLng = (log['end_lng'] as num?)?.toDouble();
      final String? imagePath = log['image_path'] as String?;
      if (imagePath != null && imagePath.trim().isNotEmpty) {
        final file = File(imagePath);
        if (file.existsSync()) {
          _capturedImage = file;
        }
      }
      _showWaypointField = (log['waypoint'] != null && log['waypoint'].toString().isNotEmpty);
      _captureGrossAndApplyDeductions();
    } else {
      final def = widget.initialDate ?? WorkDateUtils.effectiveWorkDateYmd();
      _workDateCon.text = def;
      _dateCon.text = def;
      _timeCon.text = DateFormat('HH:mm').format(DateTime.now());
      _showWaypointField = false;
      _syncedEffectiveYmd = widget.initialDate == null ? def : null;
      if (widget.initialDate == null) {
        _autoWorkDateRollActive = true;
        WidgetsBinding.instance.addObserver(this);
        _workDateRollTimer = Timer.periodic(const Duration(minutes: 1), (_) => _maybeRollEffectiveWorkDates());
      }
    }

    if (widget.quickPanel && widget.fromOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runOverlayAutoCaptureFlow();
      });
    }
  }

  Future<void> _runOverlayAutoCaptureFlow() async {
    if (_overlayAutoOcrHandled || !mounted) return;
    _overlayAutoOcrHandled = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('pending_capture_path')?.trim() ?? '';
      await prefs.remove('pending_capture_path');
      if (path.isEmpty) return;
      final file = File(path);
      if (!file.existsSync()) return;

      setState(() => _capturedImage = file);

      final inputImage = InputImage.fromFilePath(file.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final parsed = _detectProgramAndParse(recognizedText);
      if (!parsed) return;

      final canAutoSave = _parseMoney(_incomeCon.text) > 0 &&
          _startLocCon.text.trim().isNotEmpty &&
          _endLocCon.text.trim().isNotEmpty;
      if (!canAutoSave || !mounted) return;

      await _saveDriveLog();
    } catch (_) {}
  }

  void _maybeRollEffectiveWorkDates() {
    if (!_autoWorkDateRollActive || !mounted) return;
    if (_logId != null || widget.existingLog != null || widget.initialDate != null) return;
    if (_manualWorkDateRoll) return;

    final w = _workDateCon.text.trim();
    final d = _dateCon.text.trim();
    if (w.isEmpty || d.isEmpty || w != d) {
      _manualWorkDateRoll = true;
      return;
    }

    final cur = WorkDateUtils.effectiveWorkDateYmd();
    if (w == cur) return;

    if (_syncedEffectiveYmd != null && w != _syncedEffectiveYmd) {
      _manualWorkDateRoll = true;
      return;
    }

    setState(() {
      _workDateCon.text = cur;
      _dateCon.text = cur;
      _syncedEffectiveYmd = cur;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeRollEffectiveWorkDates();
    }
  }

  @override
  void dispose() {
    if (_autoWorkDateRollActive) {
      WidgetsBinding.instance.removeObserver(this);
      _workDateRollTimer?.cancel();
    }
    _workDateCon.dispose();
    _dateCon.dispose(); _timeCon.dispose(); _incomeCon.dispose(); _transportCon.dispose(); _waypointTipCon.dispose();
    _startLocCon.dispose(); _waypointCon.dispose(); _endLocCon.dispose(); _memoCon.dispose();
    super.dispose();
  }

  Future<void> _openGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _capturedImage = File(image.path));
    
    final inputImage = InputImage.fromFilePath(image.path);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
    final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();
    
    _detectProgramAndParse(recognizedText);
  }

  String? _detectProgramFromBlocks(List<TextBlock> blocks) {
    for (final b in blocks) {
      if (b.text.contains("고객과 통화")) return "카카오";
      if (b.text.contains("갱신")) return "로지";
      if (b.text.contains("출도")) return "콜마너";
    }
    return null;
  }

  bool _detectProgramAndParse(RecognizedText recognizedText) {
    List<TextBlock> blocks = List.from(recognizedText.blocks);
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final detected = _detectProgramFromBlocks(blocks);
    if (detected == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("인식불가한 이미지입니다.")),
        );
      }
      return false;
    }

    setState(() { _selectedProgram = detected; });

    _timeCon.clear(); _incomeCon.clear(); _transportCon.clear();
    _startLocCon.clear(); _waypointCon.clear(); _endLocCon.clear(); _memoCon.clear();

    if (detected == "카카오") _parseKakao(blocks);
    else if (detected == "로지") _parseLogi(blocks);
    else if (detected == "콜마너") _parseColmanner(blocks);

    _captureGrossAndApplyDeductions();
    return true;
  }

  void _parseKakao(List<TextBlock> blocks) {
    String? parsedDate; String? parsedTime; String parsedWaypoint = "";
    final StringBuffer startLocBuffer = StringBuffer(); final StringBuffer endLocBuffer = StringBuffer();
    String? parsedIncome;

    for (var b in blocks) {
      final double y = b.boundingBox.top;
      final String text = b.text.trim();
      if (y < 200) {
        final dateMatch = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(text);
        if (dateMatch != null) parsedDate = "${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}";
        final timeMatch = RegExp(r'\d{1,2}:\d{1,2}').firstMatch(text);
        if (timeMatch != null) {
          parsedTime = normalizeDriveTimeHm(timeMatch.group(0)!) ?? timeMatch.group(0)!;
        }
      }
      if (text.contains("경유")) { parsedWaypoint = text.replaceAll("경유", "").trim(); continue; }
      if (y > 500 && y < 900 && !text.contains(RegExp(r'배정|메뉴|완료|취소'))) startLocBuffer.write("$text ");
      if (y > 900 && y < 1400) endLocBuffer.write("$text ");
      if (y > 1400 && text.contains(RegExp(r'\d{3,}'))) {
        final String cleanNum = text.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanNum.length >= 4) parsedIncome = NumberFormat('#,###').format(int.parse(cleanNum));
      }
    }

    setState(() {
      if (parsedDate != null) _dateCon.text = parsedDate;
      if (parsedTime != null) _timeCon.text = parsedTime;
      if (parsedTime == null || parsedTime.isEmpty) {
        final now = DateTime.now();
        _timeCon.text = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      }
      _waypointCon.text = parsedWaypoint;
      _startLocCon.text = startLocBuffer.toString().trim();
      _endLocCon.text = endLocBuffer.toString().trim();
      if (parsedIncome != null) _incomeCon.text = parsedIncome;
    });
  }

  void _parseLogi(List<TextBlock> blocks) {
    final noiseList = ['완료', '배차', '경로', '지도', '처리', '취소', '안내', '닫기', '서명', '갱신', '고객ID', '오더번호', '차량번호', '출도', '전화', '전화2', '적요', '메모', '법인', '고객', '도착', '연기', '상황실', '발주사', '이용개시번호', '통화'];
    final labelList = ['도착지', '출발지', '요금', '입금액'];
    final List<TextBlock> sortedBlocks = List.from(blocks)..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    bool startParsed = false; bool endParsed = false;
    String parsedTime = ""; String parsedIncome = ""; String parsedStart = ""; String parsedEnd = "";

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
        if (n != null) parsedIncome = NumberFormat('#,###').format(n);
      }

      if (text == "출발지" && !startParsed) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sortedBlocks.length) {
            final String neighbor = sortedBlocks[j].text.trim();
            if (!noiseList.contains(neighbor) && !labelList.contains(neighbor) && neighbor.length > 5) addr += (addr.isEmpty ? "" : " ") + neighbor;
          }
        }
        if (addr.isNotEmpty && !addr.contains("도착")) { parsedStart = addr.replaceAll("상세:", "").trim(); startParsed = true; }
      }

      if (text == "도착지" && !endParsed) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sortedBlocks.length) {
            final String neighbor = sortedBlocks[j].text.trim();
            if (!noiseList.contains(neighbor) && !labelList.contains(neighbor) && neighbor.length > 3) addr += (addr.isEmpty ? "" : " ") + neighbor;
          }
        }
        if (addr.isNotEmpty) { parsedEnd = addr.trim(); endParsed = true; }
      }
    }

    setState(() {
      if (parsedTime.isNotEmpty) _timeCon.text = parsedTime;
      if (parsedIncome.isNotEmpty) _incomeCon.text = parsedIncome;
      if (parsedStart.isNotEmpty) _startLocCon.text = parsedStart;
      if (parsedEnd.isNotEmpty) _endLocCon.text = parsedEnd;
    });
  }

  void _parseColmanner(List<TextBlock> blocks) {
    final List<TextBlock> sorted = List.from(blocks)..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final noiseList = ['완료', '배차', '경로', '지도', '처리', '취소', '안내', '닫기', '서명', '갱신', '오더번호', '출도', '전화', '적요', '메모', '법인', '고객', '도착', '연기', '상황실', '발주사', '이용개시번호', '통화', '합계', '수수료', '보험료', '차감합계', '입금합계', '예상', '고객위치', '길안내', '운행'];
    String parsedTime = ""; String parsedIncome = ""; String parsedStart = ""; String parsedEnd = "";

    for (int i = 0; i < sorted.length; i++) {
      final String text = sorted[i].text.trim();
      final String cleanText = text.replaceAll(RegExp(r'\s+'), '').replaceAll('그', '7').replaceAll('l', '1').replaceAll('o', '0');
      final double y = sorted[i].boundingBox.top;

      if (y < 250 && parsedTime.isEmpty) {
        final tMatch = RegExp(r'(\d{1,2}[:：\.]\d{1,2})').firstMatch(cleanText);
        if (tMatch != null) {
          final timeStr = tMatch.group(1)!.replaceAll('.', ':').replaceAll('：', ':');
          parsedTime = normalizeDriveTimeHm(timeStr) ?? timeStr;
        }
      }

      if (cleanText.contains("요금")) {
        final matches = RegExp(r'\d{4,6}').allMatches(cleanText.replaceAll(',', ''));
        if (matches.isNotEmpty) {
          final List<int> prices = matches.map((m) => int.parse(m.group(0)!)).toList()..sort((a, b) => b.compareTo(a));
          if (prices.isNotEmpty) parsedIncome = NumberFormat('#,###').format(prices.first);
        }
      }

      if (text.contains("출발지")) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sorted.length) {
            final String n = sorted[j].text.trim();
            if (!noiseList.contains(n) && n.length > 3 && !n.contains("도착")) addr += (addr.isEmpty ? "" : " ") + n;
          }
        }
        if (addr.isNotEmpty) parsedStart = addr.trim();
      }

      if (text.contains("도착지")) {
        String addr = "";
        for (int j in [i - 1, i + 1]) {
          if (j >= 0 && j < sorted.length) {
            final String n = sorted[j].text.trim();
            if (!noiseList.contains(n) && n.length > 3 && !n.contains("출발")) addr += (addr.isEmpty ? "" : " ") + n;
          }
        }
        if (addr.isNotEmpty) parsedEnd = addr.trim();
      }
    }

    setState(() {
      if (parsedTime.isNotEmpty) _timeCon.text = parsedTime;
      if (parsedTime.isEmpty) {
        final now = DateTime.now();
        _timeCon.text = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      }
      if (parsedIncome.isNotEmpty) _incomeCon.text = parsedIncome;
      if (parsedStart.isNotEmpty) _startLocCon.text = parsedStart;
      if (parsedEnd.isNotEmpty) _endLocCon.text = parsedEnd;
    });
  }

  Future<void> _showWorkDateQuickPicker() async {
    final DateTime base = WorkDateUtils.effectiveWorkDateStartOfDay();
    final DateFormat formatter = DateFormat('yyyy-MM-dd');
    final List<DateTime> options = [base.subtract(const Duration(days: 1)), base, base.add(const Duration(days: 1))];

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((date) => ListTile(title: Text(formatter.format(date), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)), onTap: () => Navigator.of(context).pop(date))).toList(),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _manualWorkDateRoll = true;
      _syncedEffectiveYmd = null;
      _workDateCon.text = formatter.format(picked);
    });
  }

  Future<void> _showDateQuickPicker() async {
    final DateTime base = WorkDateUtils.effectiveWorkDateStartOfDay();
    final DateFormat formatter = DateFormat('yyyy-MM-dd');
    final List<DateTime> options = [base.subtract(const Duration(days: 1)), base, base.add(const Duration(days: 1))];

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((date) => ListTile(title: Text(formatter.format(date), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)), onTap: () => Navigator.of(context).pop(date))).toList(),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _manualWorkDateRoll = true;
      _syncedEffectiveYmd = null;
      _dateCon.text = formatter.format(picked);
    });
  }

  Future<void> _showTimeQuickPicker() async {
    final TimeOfDay initialTime = _parseTimeText(_timeCon.text) ?? TimeOfDay.now();
    int selectedHour = initialTime.hour; int selectedMinute = initialTime.minute;
    final FixedExtentScrollController hourController = FixedExtentScrollController(initialItem: selectedHour);
    final FixedExtentScrollController minuteController = FixedExtentScrollController(initialItem: selectedMinute);

    final TimeOfDay? picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        content: SizedBox(
          height: 180,
          child: Row(
            children: [
              Expanded(child: CupertinoPicker(scrollController: hourController, itemExtent: 36, onSelectedItemChanged: (value) => selectedHour = value, children: List.generate(24, (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)))))),
              const Center(child: Text(":", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
              Expanded(child: CupertinoPicker(scrollController: minuteController, itemExtent: 36, onSelectedItemChanged: (value) => selectedMinute = value, children: List.generate(60, (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)))))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("취소", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.of(context).pop(TimeOfDay(hour: selectedHour, minute: selectedMinute)), child: Text("확인", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFC700)))),
        ],
      ),
    );

    hourController.dispose(); minuteController.dispose();
    if (picked == null) return;
    setState(() { _timeCon.text = _formatTime24(picked); });
  }

  TimeOfDay? _parseTimeText(String value) {
    final nt = normalizeDriveTimeHm(value);
    if (nt == null) return null;
    final parts = nt.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
  String _formatTime24(TimeOfDay time) => "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

  Future<void> _openNaverMapRoute() async {
    final String start = _startLocCon.text.trim(); final String end = _endLocCon.text.trim();
    if (start.isEmpty || end.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("출발지와 도착지를 먼저 입력해 주세요."))); return;
    }
    final String startN = normalizeAddressForGeocode(start);
    final String endN = normalizeAddressForGeocode(end);
    try {
      final List<Location> startLocations = await locationFromAddress(startN.isNotEmpty ? startN : start);
      final List<Location> endLocations = await locationFromAddress(endN.isNotEmpty ? endN : end);
      if (startLocations.isNotEmpty && endLocations.isNotEmpty) {
        final Location startLoc = startLocations.first; final Location endLoc = endLocations.first;
        final Uri naverRouteUri = Uri(scheme: "nmap", host: "route", path: "car", queryParameters: {"slat": startLoc.latitude.toStringAsFixed(7), "slng": startLoc.longitude.toStringAsFixed(7), "sname": startN.isNotEmpty ? startN : start, "dlat": endLoc.latitude.toStringAsFixed(7), "dlng": endLoc.longitude.toStringAsFixed(7), "dname": endN.isNotEmpty ? endN : end});
        if (Platform.isAndroid) {
          final AndroidIntent naverIntent = AndroidIntent(action: "action_view", data: naverRouteUri.toString(), package: "com.nhn.android.nmap");
          try { await naverIntent.launch(); return; } catch (_) {
            await AndroidIntent(action: "action_view", data: "market://details?id=com.nhn.android.nmap").launch(); return;
          }
        } else {
          if (await canLaunchUrl(naverRouteUri)) { await launchUrl(naverRouteUri, mode: LaunchMode.externalApplication); return; }
        }
      }
    } catch (_) {}
    await launchUrl(Uri.parse("https://map.naver.com/v5/search/${Uri.encodeComponent("${startN.isNotEmpty ? startN : start} ${endN.isNotEmpty ? endN : end} 길찾기")}"), mode: LaunchMode.externalApplication);
  }

  Future<void> _openStartMapPicker() async {
    final LatLng? result = await Navigator.push<LatLng?>(
      context,
      MaterialPageRoute<LatLng?>(
        builder: (_) => LocationPickMapPage(
          addressQuery: _startLocCon.text,
          initialLatLng: _startLat != null && _startLng != null ? LatLng(_startLat!, _startLng!) : null,
          title: '출발 위치',
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _startLat = result.latitude;
      _startLng = result.longitude;
    });
  }

  Future<void> _openEndMapPicker() async {
    final LatLng? result = await Navigator.push<LatLng?>(
      context,
      MaterialPageRoute<LatLng?>(
        builder: (_) => LocationPickMapPage(
          addressQuery: _endLocCon.text,
          initialLatLng: _endLat != null && _endLng != null ? LatLng(_endLat!, _endLng!) : null,
          title: '도착 위치',
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _endLat = result.latitude;
      _endLng = result.longitude;
    });
  }

  Widget _pinPickButton({required bool forStart}) {
    final has = forStart
        ? _startLat != null && _startLng != null
        : _endLat != null && _endLng != null;
    return IconButton(
      icon: Icon(
        Icons.add_location_alt,
        color: has ? Colors.redAccent : const Color(0xFFFFC700),
        size: 22,
      ),
      onPressed: forStart ? _openStartMapPicker : _openEndMapPicker,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      tooltip: forStart ? '출발 좌표' : '도착 좌표',
    );
  }

  int _parseMoney(String value) => int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  String _formatMoney(int value) => NumberFormat('#,###').format(value);
  
  int _currentFeeFromGross() => SettingsService.deductionFeeFromGross(_grossIncome, _selectedProgram);
  
  /// 경유비(팁)는 수수료·교통비처럼 차감이 아니라 순수익에 **가산**됩니다.
  int _currentNetIncomeFromGross() => (_grossIncome - _currentFeeFromGross() - _parseMoney(_transportCon.text) + _parseMoney(_waypointTipCon.text)).clamp(0, 999999999);

  void _captureGrossAndApplyDeductions() { _grossIncome = _parseMoney(_incomeCon.text); _applyDeductions(); }
  void _applyDeductions() {
    _grossIncome = _parseMoney(_incomeCon.text);
    final int transport = _parseMoney(_transportCon.text);
    final int waypointTip = _parseMoney(_waypointTipCon.text);
    final int fee = _currentFeeFromGross();
    final int net = (_grossIncome - fee - transport + waypointTip).clamp(0, 999999999);
    final int deductOnly = fee + transport;
    setState(() {
      _deductionHint = _grossIncome > 0
          ? "순수익 ${_formatMoney(net)}원 (차감 ${_formatMoney(deductOnly)}원)"
          : "";
    });
  }

  Future<void> _maybePromptNextDriveDay() async {
    final w = _workDateCon.text.trim();
    final d = _dateCon.text.trim();
    if (w.isEmpty || d.isEmpty) return;
    if (w != d) return;
    final h = WorkDateUtils.hourFromHm(_timeCon.text);
    if (h > 1) return;
    if (!mounted) return;
    final next = WorkDateUtils.addDays(w, 1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        title: const Text('운행 날짜 확인', style: TextStyle(color: Colors.white)),
        content: Text(
          '운행 시간이 새벽(00~01시)입니다.\n운행 날짜를 다음 날($next)로 설정할까요?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오', style: TextStyle(color: Color(0xFF6E717C)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('예', style: TextStyle(color: Color(0xFFFFC700)))),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _dateCon.text = next);
    }
  }

  Future<void> _saveDriveLog() async {
    if (_workDateCon.text.trim().isEmpty || _dateCon.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("근무일자·운행 날짜를 확인해 주세요.")));
      return;
    }
    await _maybePromptNextDriveDay();
    if (!mounted) return;

    _grossIncome = _parseMoney(_incomeCon.text);
    final String nowIso = DateTime.now().toIso8601String();

    final Map<String, dynamic> row = {
      if (_logId != null) "id": _logId,
      "work_date": _workDateCon.text.trim(),
      "drive_date": _dateCon.text.trim(),
      "drive_time": resolveDriveTimeForStorage(_timeCon.text),
      "program": _selectedProgram,
      "gross_fare": _grossIncome, "fee": _currentFeeFromGross(), "transport_cost": _parseMoney(_transportCon.text),
      "waypoint_tip": _parseMoney(_waypointTipCon.text),
      "net_income": _currentNetIncomeFromGross(), "start_location": _startLocCon.text.trim(),
      "waypoint": _waypointCon.text.trim(), "end_location": _endLocCon.text.trim(), "memo": _memoCon.text.trim(),
      "start_lat": _startLat,
      "start_lng": _startLng,
      "end_lat": _endLat,
      "end_lng": _endLng,
      "image_path": _capturedImage?.path,
      "updated_at": nowIso,
      if (_logId == null)
        "created_at": nowIso
      else if (widget.existingLog != null && widget.existingLog!['created_at'] != null)
        "created_at": widget.existingLog!['created_at'].toString(),
    };

    try {
      await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("저장 중 오류가 발생했습니다.")));
      return;
    }

    if (!mounted) return;
    final String workStr = _workDateCon.text.trim();
    final String savedMsg =
        _logId != null ? "운행일지가 수정되었습니다." : "운행일지가 등록되었습니다.";

    if (widget.fromOverlay) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(savedMsg)));
      await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    MainTabScope.maybeOf(context)?.selectTab(1);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => DailyLogListPage(
          dateStr: workStr,
          dateTitle: '근무일자: $workStr',
          snackMessage: savedMsg,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 12.0 : 10.0;
    final iconSize = isTablet ? 26 : 24;

    final form = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      child: widget.quickPanel ? _buildQuickPanelFormLayout() : _buildFormLayout(),
    );

    if (widget.quickPanel) {
      const double quickUiOpacity = 0.7;
      final closeQuickPanel = () async {
        if (widget.fromOverlay) {
          await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
        }
        if (widget.fromOverlay && await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        } else if (mounted) {
          Navigator.pop(context);
        }
      };

      final header = SafeArea(
        bottom: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isTablet ? 12.0 : 8.0,
            isTablet ? 8.0 : 6.0,
            isTablet ? 12.0 : 8.0,
            isTablet ? 8.0 : 6.0,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1F222A),
            border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: iconSize.toDouble()),
                onPressed: closeQuickPanel,
              ),
              Expanded(
                child: Text(
                  '퀵 등록',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFFFC700),
                      ),
                ),
              ),
              TextButton(
                onPressed: _saveDriveLog,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC700).withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
                ),
                child: Text(
                  '등록',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFFFC700),
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
        ),
      );

      final footer = SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isTablet ? 12.0 : 8.0,
            isTablet ? 8.0 : 6.0,
            isTablet ? 12.0 : 8.0,
            isTablet ? 10.0 : 8.0,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1F222A),
            border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: closeQuickPanel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF6E717C)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 10),
                  ),
                  child: const Text('닫기', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveDriveLog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC700),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 10),
                  ),
                  child: const Text('등록', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );

      return Opacity(
        opacity: quickUiOpacity,
        child: Scaffold(
          backgroundColor: const Color(0xCC000000),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 520 : screenWidth * 0.94, maxHeight: MediaQuery.sizeOf(context).height * 0.88),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: const Color(0xFF121418),
                  child: Column(
                    children: [
                      header,
                      Expanded(child: form),
                      footer,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F222A),
        leading: _logId != null || widget.initialDate != null
          ? IconButton(icon: Icon(Icons.arrow_back, color: Colors.white, size: iconSize.toDouble()), onPressed: () => Navigator.pop(context)) 
          : null,
        title: Text(_logId != null ? "운행 일지 수정" : "운행 일지 작성", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFFFC700))),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: isTablet ? 12.0 : 8.0),
            child: TextButton(
              onPressed: _saveDriveLog, 
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700).withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
              ),
              child: Text(_logId != null ? "수정" : "등록", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold))
            ),
          )
        ],
      ),
      body: form,
    );
  }

  /// 퀵 패널: 요금 · 출발 · 도착 (+경유). 일자·시간·프로그램은 초기값·설정값으로 저장 시 사용.
  Widget _buildQuickPanelFormLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputGroup("요금", Icons.payments_outlined, [
            _buildDropdown(),
            _buildInputField(
              _incomeCon,
              label: "요금",
              isNumber: true,
              onChanged: (_) {
                _captureGrossAndApplyDeductions();
                _applyDeductions();
              },
              suffixWidget: _deductionHint.isNotEmpty
                  ? Text(_deductionHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.w500))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '일자·시간은 기본값으로 반영 (${_workDateCon.text} ${_timeCon.text})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A8D96), fontSize: 11),
              ),
            ),
          ], trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_capturedImage != null)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  icon: const Icon(Icons.image, color: Color(0xFFFFC700)),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFFFC700), width: 2.0),
                          ),
                          child: Image.file(_capturedImage!),
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                icon: const Icon(Icons.style, color: Color(0xFFFFC700)),
                onPressed: _openGallery,
              ),
            ],
          )),
          const SizedBox(height: 14),
          _buildInputGroup("운행 경로", Icons.directions, [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("출발지", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_showWaypointField && _waypointCon.text.trim().isEmpty) {
                            _showWaypointField = false;
                          } else {
                            _showWaypointField = true;
                          }
                        });
                      },
                      child: Text(
                        "+경유",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFFFC700),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _startLocCon,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF121418),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFC700))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: _pinPickButton(forStart: true),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
            if (_showWaypointField) _buildInputField(_waypointCon, label: "경유지"),
            _buildInputField(_endLocCon, label: "도착지", suffixIcon: _pinPickButton(forStart: false)),
          ]),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                _captureGrossAndApplyDeductions();
                final draft = <String, dynamic>{
                  'work_date': _workDateCon.text.trim(),
                  'drive_date': _dateCon.text.trim(),
                  'drive_time': resolveDriveTimeForStorage(_timeCon.text),
                  'program': _selectedProgram,
                  'gross_fare': _parseMoney(_incomeCon.text),
                  'fee': _currentFeeFromGross(),
                  'transport_cost': _parseMoney(_transportCon.text),
                  'waypoint_tip': _parseMoney(_waypointTipCon.text),
                  'net_income': _currentNetIncomeFromGross(),
                  'start_location': _startLocCon.text.trim(),
                  'waypoint': _waypointCon.text.trim(),
                  'end_location': _endLocCon.text.trim(),
                  'memo': '',
                  if (_startLat != null) 'start_lat': _startLat,
                  if (_startLng != null) 'start_lng': _startLng,
                  if (_endLat != null) 'end_lat': _endLat,
                  if (_endLng != null) 'end_lng': _endLng,
                };
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => DriveLogForm(existingLog: draft),
                  ),
                );
              },
              child: Text(
                '전체 항목으로 작성',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFFFC700),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFFFC700),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildInputGroup("근무·운행 일자 및 시간", Icons.access_time_filled, [
            _buildInputField(_workDateCon, label: "근무 일자", readOnly: true, onTap: _showWorkDateQuickPicker),
            Row(
              children: [
                Expanded(child: _buildInputField(_dateCon, label: "운행 일자", readOnly: true, onTap: _showDateQuickPicker, bottomMargin: 0)),
                const SizedBox(width: 12),
                Expanded(child: _buildInputField(_timeCon, label: "운행 시간", readOnly: true, onTap: _showTimeQuickPicker, bottomMargin: 0)),
              ],
            ),
          ]),
          const SizedBox(height: 20),
          _buildInputGroup(
            "프로그램 및 금액", Icons.account_balance_wallet, 
            [
              _buildDropdown(),
              _buildInputField(_incomeCon, label: "운행 요금", isNumber: true, onChanged: (_) => _captureGrossAndApplyDeductions(), suffixWidget: _deductionHint.isNotEmpty ? Text(_deductionHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.w500)) : null),
              Row(
                children: [
                  Expanded(child: _buildInputField(_transportCon, label: "교통비", isNumber: true, onChanged: (_) => _applyDeductions())),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInputField(_waypointTipCon, label: "경유비(팁)", isNumber: true, onChanged: (_) => _applyDeductions())),
                ],
              ),
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_capturedImage != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                    icon: const Icon(Icons.image, color: Color(0xFFFFC700)),
                    onPressed: () => showDialog(
                      context: context, 
                      builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context), 
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFC700), width: 2.0)),
                            child: Image.file(_capturedImage!)
                          )
                        )
                      )
                    ),
                  ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  icon: const Icon(Icons.style, color: Color(0xFFFFC700)),
                  onPressed: _openGallery,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildInputGroup("운행 경로", Icons.directions, [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("출발지", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_showWaypointField && _waypointCon.text.trim().isEmpty) {
                            _showWaypointField = false;
                          } else {
                            _showWaypointField = true;
                          }
                        });
                      },
                      child: Text(
                        "+경유추가",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFFC700),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _startLocCon,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF121418),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFC700))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: _pinPickButton(forStart: true),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
            if (_showWaypointField) _buildInputField(_waypointCon, label: "경유지"),
            _buildInputField(_endLocCon, label: "도착지", suffixIcon: _pinPickButton(forStart: false)),
          ], trailing: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: const Icon(Icons.map, color: Color(0xFFFFC700)),
            onPressed: _openNaverMapRoute,
          )),
          const SizedBox(height: 20),
          _buildInputGroup("메모", Icons.note, [_buildInputField(_memoCon, label: "특이사항", maxLines: 3)]),
        ],
      ),
    );
  }

  Widget _buildInputGroup(String title, IconData icon, List<Widget> children, {Widget? trailing}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFFFC700), size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'GmarketSans',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailing != null) ...[const Spacer(), trailing],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, {required String label, bool isNumber = false, VoidCallback? onTap, bool readOnly = false, double bottomMargin = 16, int maxLines = 1, Widget? suffixWidget, Widget? suffixIcon, Function(String)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
          maxLines: maxLines,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
          decoration: InputDecoration(
            suffix: suffixWidget,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF121418),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFFC700))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        SizedBox(height: bottomMargin),
      ],
    );
  }

  Widget _buildDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("프로그램", style: TextStyle(color: Color(0xFF6E717C), fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF121418),
            border: Border.all(color: Colors.white10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedProgram,
              dropdownColor: const Color(0xFF1F222A),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
              items: SettingsService.programList.map((program) {
                return DropdownMenuItem<String>(
                  value: program,
                  child: Text(program),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedProgram = value;
                    _captureGrossAndApplyDeductions();
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

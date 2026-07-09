import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) '../utils/maps_web_stub.dart';
import '../services/db_helper.dart';
import '../services/image_storage_service.dart';
import '../services/settings_service.dart';
import '../services/today_stats_notification_service.dart';
import '../services/ocr_parse_log_service.dart';
import '../main_navigation.dart';
import '../providers/guide_provider.dart';
import '../providers/work_timer_provider.dart'; // [자동출근] 일지 등록 시 미출근이면 자동 출근 처리
import '../utils/drive_time_format.dart';
import '../utils/logi_colmanner_ocr.dart';
import '../utils/responsive_layout.dart';
import '../utils/work_date_utils.dart';
import '../widgets/app_glass_dialog.dart';
import '../widgets/bordered_section.dart';
import '../widgets/guide_content_widget.dart';
import '../widgets/responsive_body.dart';
import '../widgets/drive_log_source_chip.dart';
import '../utils/tmap_trip_detail_ocr.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/ocr_failure_feedback.dart';
import '../utils/app_bottom_sheet.dart';
import '../utils/address_normalize.dart';
import '../config/feature_flags.dart';
import '../utils/formatters.dart';
import '../utils/app_image_picker.dart';
import '../utils/pro_feature_guard.dart';
import '../services/feature_usage_service.dart';
import 'location_pick_map_page.dart';
import 'log_list_page.dart';

class DriveLogForm extends StatefulWidget {
  final Map<String, dynamic>? existingLog;
  final String? initialDate;
  /// 알림 퀵등록 등: 반투명 배경 위 카드 형태 간소 표시
  final bool quickPanel;
  /// 시스템 오버레이로 띄운 경우(다른 앱 위 레이어). 저장 후 리스트 네비 대신 오버레이 종료.
  final bool fromOverlay;
  /// 다른 앱에서 이미지 공유(SEND)로 전달된 로컬 경로 — 열자마자 OCR 시도
  final String? sharedImagePath;
  const DriveLogForm({
    super.key,
    this.existingLog,
    this.initialDate,
    this.quickPanel = false,
    this.fromOverlay = false,
    this.sharedImagePath,
  });

  @override
  State<DriveLogForm> createState() => _DriveLogFormState();

  @visibleForTesting
  static void testAppendMemoFromField(BuildContext context, {required String category, required String amountStr}) {
    if (context is StatefulElement) {
      final state = context.state as _DriveLogFormState;
      state._appendMemoFromField(category: category, amountStr: amountStr);
    }
  }

  @visibleForTesting
  static String getTestMemoText(BuildContext context) {
    if (context is StatefulElement) {
      final state = context.state as _DriveLogFormState;
      return state._memoCon.text;
    }
    return '';
  }

  @visibleForTesting
  static void setTestMemoText(BuildContext context, String text) {
    if (context is StatefulElement) {
      final state = context.state as _DriveLogFormState;
      state._memoCon.text = text;
    }
  }
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
  /// DB에 이미 들어있는 등록 출처(스크린샷 자동 등). 수정 시 유지한다.
  String? _persistedRegistrationSource;

  int _grossIncome = 0;
  String _deductionHint = "";
  String _selectedProgram =
      SettingsService.programList.isNotEmpty ? SettingsService.programList.first : "카카오(일반)";
  File? _capturedImage;
  bool _showWaypointField = false;

  bool _manualWorkDateRoll = false;
  String? _syncedEffectiveYmd;
  Timer? _workDateRollTimer;
  bool _autoWorkDateRollActive = false;
  bool _overlayAutoOcrHandled = false;
  int _driveTimeDefaultGen = 0;

  // FocusNodes for transport and waypoint tip to detect focus loss (focus out)
  final FocusNode _transportFocusNode = FocusNode();
  final FocusNode _waypointTipFocusNode = FocusNode();
  final FocusNode _startLocFocusNode = FocusNode();
  final FocusNode _endLocFocusNode = FocusNode();
  final FocusNode _waypointFocusNode = FocusNode();
  final FocusNode _incomeFocusNode = FocusNode();
  final FocusNode _memoFocusNode = FocusNode();

  // Category selections
  String _selectedExpenseCategory = SettingsService.expenseList.isNotEmpty ? SettingsService.expenseList.first : '기타';
  String _selectedExtraIncomeCategory = SettingsService.incomeList.isNotEmpty ? SettingsService.incomeList.first : '기타';

  /// 신규 작성: false면 저장 시 운행시각을 **등록 시점**으로 쓴다. OCR 비어 있음·갤러리 폴백 시각은 여기 해당.
  /// true: OCR이 운행시각을 채웠거나 사용자가 시간 피커로 고른 경우 → [_timeCon] 사용.
  bool _useFormDriveTimeOnSave = false;

  double? _startLat;
  double? _startLng;
  double? _endLat;
  double? _endLng;

  // Guide Keys
  final GlobalKey _keyOcrBtn = GlobalKey();
  final GlobalKey _keyTimeSection = GlobalKey();
  final GlobalKey _keyFinanceSection = GlobalKey();
  final GlobalKey _keyLocationSection = GlobalKey();
  final GlobalKey _keyMemoSection = GlobalKey();
  final GlobalKey _keySaveBtn = GlobalKey();

  @override
  void initState() {
    super.initState();
    _transportFocusNode.addListener(_onTransportFocusChanged);
    _waypointTipFocusNode.addListener(_onWaypointTipFocusChanged);
    _selectedProgram = _coerceProgramForSelection(_selectedProgram);
    if (widget.existingLog != null) {
      final log = widget.existingLog!;
      _logId = log['id'];
      final rs = log['registration_source']?.toString().trim();
      _persistedRegistrationSource = rs != null && rs.isNotEmpty ? rs : null;
      _workDateCon.text = (log['work_date'] ?? log['drive_date'])?.toString() ?? '';
      _dateCon.text = log['drive_date']?.toString() ?? '';
      _timeCon.text = normalizeDriveTimeHm(log['drive_time']?.toString()) ?? log['drive_time']?.toString() ?? '';
      _selectedProgram = _coerceProgramForSelection(log['program']?.toString());
      _incomeCon.text = NumberFormat('#,###').format(log['gross_fare']);
      _transportCon.text = log['transport_cost'] > 0 ? NumberFormat('#,###').format(log['transport_cost']) : '';
      _waypointTipCon.text = log['waypoint_tip'] != null && log['waypoint_tip'] > 0 ? NumberFormat('#,###').format(log['waypoint_tip']) : '';
      final savedExpenseCat = log['expense_category']?.toString();
      if (savedExpenseCat != null && savedExpenseCat.isNotEmpty) {
        _selectedExpenseCategory = SettingsService.expenseList.contains(savedExpenseCat) ? savedExpenseCat : _selectedExpenseCategory;
      }
      final savedIncomeCat = log['income_category']?.toString();
      if (savedIncomeCat != null && savedIncomeCat.isNotEmpty) {
        _selectedExtraIncomeCategory = SettingsService.incomeList.contains(savedIncomeCat) ? savedIncomeCat : _selectedExtraIncomeCategory;
      }
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
      _useFormDriveTimeOnSave = true;
    } else {
      _useFormDriveTimeOnSave = false;
      final def = widget.initialDate ?? WorkDateUtils.effectiveWorkDateYmd();
      _workDateCon.text = def;
      _timeCon.text = DateFormat('HH:mm').format(DateTime.now());
      _dateCon.text = WorkDateUtils.resolveDriveDateForNightShift(def, _timeCon.text);
      _showWaypointField = false;
      _syncedEffectiveYmd = widget.initialDate == null ? def : null;
      if (widget.initialDate == null) {
        _autoWorkDateRollActive = true;
        WidgetsBinding.instance.addObserver(this);
        _workDateRollTimer = Timer.periodic(const Duration(minutes: 1), (_) => _maybeRollEffectiveWorkDates());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _applyDefaultDriveTimeForNewLog();
        final sp = widget.sharedImagePath?.trim();
        if (sp != null && sp.isNotEmpty) {
          await _runOcrOnSharedPath(sp);
        }
      });
    }

    if (widget.quickPanel && widget.fromOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runOverlayAutoCaptureFlow();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guideProvider = Provider.of<GuideProvider>(context, listen: false);
      guideProvider.addListener(_onGuideRequested);
      if (guideProvider.pendingGuideTarget == 'write') {
        _startGuideWhenReady();
      }
    });
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

      final originalDate = file.existsSync() ? file.lastModifiedSync() : DateTime.now();
      final parsed = _detectProgramAndParse(recognizedText, originalDate: originalDate);
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

    final cur = WorkDateUtils.effectiveWorkDateYmd();
    if (_syncedEffectiveYmd == cur) return;

    setState(() {
      _workDateCon.text = cur;
      _dateCon.text = WorkDateUtils.resolveDriveDateForNightShift(cur, _timeCon.text);
      _syncedEffectiveYmd = cur;
    });
    _applyDefaultDriveTimeForNewLog();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_autoWorkDateRollActive) {
        if (_workDateRollTimer == null || !_workDateRollTimer!.isActive) {
          _workDateRollTimer = Timer.periodic(const Duration(minutes: 1), (_) => _maybeRollEffectiveWorkDates());
        }
      }
      _maybeRollEffectiveWorkDates();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _workDateRollTimer?.cancel();
    }
  }

  @override
  void dispose() {
    if (_autoWorkDateRollActive) {
      WidgetsBinding.instance.removeObserver(this);
      _workDateRollTimer?.cancel();
    }
    _transportFocusNode.dispose();
    _waypointTipFocusNode.dispose();
    _startLocFocusNode.dispose();
    _endLocFocusNode.dispose();
    _waypointFocusNode.dispose();
    _incomeFocusNode.dispose();
    _memoFocusNode.dispose();
    _workDateCon.dispose();
    _dateCon.dispose(); _timeCon.dispose(); _incomeCon.dispose(); _transportCon.dispose(); _waypointTipCon.dispose();
    _startLocCon.dispose(); _waypointCon.dispose(); _endLocCon.dispose(); _memoCon.dispose();
    
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.removeListener(_onGuideRequested);
    
    super.dispose();
  }

  Future<void> _openGallery() async {
    ProFeatureGuard.checkAndRun(
      context: context,
      featureKey: 'single_ocr',
      canUseFree: FeatureUsageService.canUseSingleOcrFree,
      canUseWithAd: FeatureUsageService.canUseSingleOcrWithAd,
      onGranted: () async {
        final result = await AppImagePicker.pickSingleGalleryImage(context);
        if (result == null) return;
        
        final file = result.file;
        setState(() => _capturedImage = file);
        
        final inputImage = InputImage.fromFilePath(file.path);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        await textRecognizer.close();
        
        _detectProgramAndParse(recognizedText, originalDate: result.creationDate);
      },
    );
  }

  /// OS 공유 시트 등에서 전달된 파일 경로로 OCR (갤러리 선택과 동일 파이프)
  Future<void> _runOcrOnSharedPath(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('공유한 이미지를 열 수 없습니다. 저장소 권한을 확인해 주세요.')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _capturedImage = file);

      final originalDate = file.existsSync() ? file.lastModifiedSync() : DateTime.now();

      final inputImage = InputImage.fromFilePath(file.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      
      if (!mounted) return;
      _detectProgramAndParse(recognizedText, originalDate: originalDate);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 이미지 처리 중 오류: $e')),
        );
      }
    }
  }

  String? _detectProgramFromBlocks(List<TextBlock> blocks, String fullText) {
    final normalized = fullText.replaceAll(RegExp(r'\s+'), '');
    for (final b in blocks) {
      if (b.text.contains("갱신")) return "로지";
      if (b.text.contains("출도")) return "콜마너";
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
    for (final b in blocks) {
      if (b.text.contains("고객과 통화")) {
        return KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          fullText,
          blocks,
          KakaoCallCardOcr.programGeneral,
        );
      }
    }
    return null;
  }

  bool _detectProgramAndParse(RecognizedText recognizedText, {DateTime? originalDate}) {
    List<TextBlock> blocks = List.from(recognizedText.blocks);
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    _useFormDriveTimeOnSave = false;

    final detected = _detectProgramFromBlocks(blocks, recognizedText.text);
    if (detected == null) {
      OcrParseLogService.record(
        source: 'write_log',
        rawText: recognizedText.text,
        parsedData: OcrParseLogService.parsedDataFrom(),
        recognized: false,
      );
      if (mounted) {
        OcrFailureFeedback.showUnrecognizedSnackbar(
          context,
          fullText: recognizedText.text,
        );
      }
      return false;
    }

    setState(() {
      _selectedProgram = _coerceProgramForSelection(detected);
    });

    _timeCon.clear(); _incomeCon.clear(); _transportCon.clear();
    _startLocCon.clear(); _waypointCon.clear(); _endLocCon.clear(); _memoCon.clear();

    if (detected == KakaoCustomCallOcr.programCustom) {
      _parseKakaoCustom(blocks, fullText: recognizedText.text);
    } else if (detected == KakaoCallCardOcr.programGeneral ||
        detected == KakaoCallCardOcr.programPro ||
        detected == KakaoCallCardOcr.programAlliance) {
      _parseKakao(blocks, fullText: recognizedText.text);
    } else if (detected == "로지") {
      _parseLogi(blocks);
    } else if (detected == "콜마너") {
      _parseColmanner(blocks);
    } else if (detected == "티맵") {
      _parseTmapTripDetail(recognizedText);
    }

    if (originalDate != null) {
      // Exif 메타데이터 기준 날짜/시간 설정 — OCR 파서가 더 이상 시간을 추출하지 않으므로
      // 여기서 _useFormDriveTimeOnSave = true 로 명시해 저장 시 Exif 시각이 쓰이도록 한다.
      _timeCon.text = formatDriveTimeHm(originalDate);
      _useFormDriveTimeOnSave = true;
      final workYmd = WorkDateUtils.effectiveWorkDateYmd(originalDate);
      _workDateCon.text = workYmd;
      _dateCon.text = WorkDateUtils.resolveDriveDateForNightShift(workYmd, _timeCon.text);
      _syncedEffectiveYmd = workYmd;
    } else {
      _syncWorkDateFromDriveDateTime();
    }

    _captureGrossAndApplyDeductions();
    final waypoints = _waypointCon.text.trim().isEmpty
        ? const <String>[]
        : [_waypointCon.text.trim()];
    OcrParseLogService.record(
      source: 'write_log',
      program: _selectedProgram,
      rawText: recognizedText.text,
      parsedData: OcrParseLogService.parsedDataFrom(
        departure: _startLocCon.text.trim(),
        destination: _endLocCon.text.trim(),
        waypoints: waypoints,
        feeAmount: _parseMoney(_incomeCon.text),
        paymentMethod: _paymentMethodFromMemo(_memoCon.text),
        driveTime: _timeCon.text.trim(),
      ),
    );
    return true;
  }

  String? _paymentMethodFromMemo(String memo) {
    final m = RegExp(r'결제방식:([^\n]+)').firstMatch(memo);
    if (m == null) return null;
    final value = m.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  void _parseKakaoCustom(List<TextBlock> blocks, {required String fullText}) {
    final p = KakaoCustomCallOcr.parseScreen(blocks, fullText);
    // driveDateYmd/driveTimeHm은 항상 null (Exif 메타데이터로 대체됨)
    String? parsedIncome;
    if (p.grossFare != null) {
      parsedIncome = NumberFormat('#,###').format(p.grossFare!);
    }

    setState(() {
      _waypointCon.text = '';
      _startLocCon.text = p.startLocation;
      _endLocCon.text = p.endLocation;
      if (parsedIncome != null) _incomeCon.text = parsedIncome;
      if ((p.paymentMethod ?? '').isNotEmpty && _memoCon.text.trim().isEmpty) {
        _memoCon.text = '결제방식:${p.paymentMethod}';
      }
    });
  }

  void _parseKakao(List<TextBlock> blocks, {required String fullText}) {
    final p = KakaoCallCardOcr.parseScreen(blocks, fullText);
    // driveDateYmd/driveTimeHm은 항상 null (Exif 메타데이터로 대체됨)
    String? parsedIncome;
    if (p.grossFare != null) {
      parsedIncome = NumberFormat('#,###').format(p.grossFare!);
    }

    setState(() {
      _waypointCon.text = p.waypoint;
      _startLocCon.text = p.startLocation;
      _endLocCon.text = p.endLocation;
      if (parsedIncome != null) _incomeCon.text = parsedIncome;
    });
  }

  void _parseLogi(List<TextBlock> blocks) {
    final sortedBlocks = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sortedBlocks.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseLogi(full, blocks: sortedBlocks);

    setState(() {
      // driveTimeHm은 항상 빈 문자열 (Exif 메타데이터로 대체됨)
      if (p.grossFare > 0) _incomeCon.text = NumberFormat('#,###').format(p.grossFare);
      if (p.startLocation.isNotEmpty) _startLocCon.text = p.startLocation;
      if (p.endLocation.isNotEmpty) _endLocCon.text = p.endLocation;
      if (p.waypoint.isNotEmpty) _waypointCon.text = p.waypoint;
    });
  }

  void _parseColmanner(List<TextBlock> blocks) {
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sorted.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseColmanner(full, blocks: sorted);

    setState(() {
      // driveTimeHm은 항상 빈 문자열 (Exif 메타데이터로 대체됨)
      if (p.grossFare > 0) _incomeCon.text = NumberFormat('#,###').format(p.grossFare);
      if (p.startLocation.isNotEmpty) _startLocCon.text = p.startLocation;
      if (p.endLocation.isNotEmpty) _endLocCon.text = p.endLocation;
      if (p.waypoint.isNotEmpty) _waypointCon.text = p.waypoint;
    });
  }

  void _parseTmapTripDetail(RecognizedText recognizedText) {
    final r = TmapTripDetailOcr.tryParse(
      recognizedText.text,
      blocks: recognizedText.blocks,
    );
    if (r == null) return;
    setState(() {
      // driveDateYmd/driveStartTimeHm은 항상 빈 문자열 (Exif 메타데이터로 대체됨)
      if (r.grossFare > 0) {
        _incomeCon.text = NumberFormat('#,###').format(r.grossFare);
      }
      if (r.startAddress.isNotEmpty) _startLocCon.text = r.startAddress;
      if (r.endAddress.isNotEmpty) _endLocCon.text = r.endAddress;
      if (r.waypoint != null && r.waypoint!.isNotEmpty) {
        _waypointCon.text = r.waypoint!;
        _showWaypointField = true;
      }
    });
  }

  Future<void> _showWorkDateQuickPicker() async {
    final DateTime initial = DateTime.tryParse(_workDateCon.text.trim()) ??
        WorkDateUtils.effectiveWorkDateStartOfDay();
    final DateTime? picked =
        await _pickDateFromMonthlyScroller(initialDate: initial, title: '근무일자 선택');
    if (picked == null) return;
    setState(() {
      _manualWorkDateRoll = true;
      _syncedEffectiveYmd = null;
      _workDateCon.text = DateFormat('yyyy-MM-dd').format(picked);
    });
    if (_logId == null && widget.existingLog == null) {
      await _applyDefaultDriveTimeForNewLog();
    }
  }

  /// 신규 작성: 해당 근무일에 일지가 있으면 마지막 운행시각+30분, 없으면 현재 시각.
  Future<void> _applyDefaultDriveTimeForNewLog() async {
    if (!mounted || _logId != null || widget.existingLog != null) return;
    final gen = ++_driveTimeDefaultGen;
    final wd = _normalizeYmdForStorage(_workDateCon.text);
    if (wd == null) return;
    final lastHm = await DriveLogDatabase.instance.getLatestDriveTimeHmOnWorkDate(wd);
    if (!mounted || gen != _driveTimeDefaultGen) return;
    final String nextHm;
    if (lastHm == null) {
      nextHm = DateFormat('HH:mm').format(DateTime.now());
    } else {
      final parts = lastHm.split(':');
      final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
      final mi = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      final base = DateTime(2000, 1, 1, h, mi);
      nextHm = formatDriveTimeHm(base.add(const Duration(minutes: 30)));
    }
    if (!mounted || gen != _driveTimeDefaultGen) return;
    setState(() {
      _timeCon.text = nextHm;
      _dateCon.text = WorkDateUtils.resolveDriveDateForNightShift(_workDateCon.text, nextHm);
    });
  }

  Future<void> _showDateQuickPicker() async {
    final DateTime initial = DateTime.tryParse(_dateCon.text.trim()) ??
        WorkDateUtils.effectiveWorkDateStartOfDay();
    final DateTime? picked =
        await _pickDateFromMonthlyScroller(initialDate: initial, title: '운행일자 선택');
    if (picked == null) return;
    setState(() {
      _manualWorkDateRoll = true;
      _syncedEffectiveYmd = null;
      _dateCon.text = DateFormat('yyyy-MM-dd').format(picked);
      _syncWorkDateFromDriveDateTime();
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
        backgroundColor: Theme.of(context).cardTheme.color!,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        content: SizedBox(
          height: 180,
          child: Row(
            children: [
              Expanded(child: CupertinoPicker(scrollController: hourController, itemExtent: 36, onSelectedItemChanged: (value) => selectedHour = value, children: List.generate(24, (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white))))))),
              Center(child: Text(":", style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), fontSize: 20, fontWeight: FontWeight.bold))),
              Expanded(child: CupertinoPicker(scrollController: minuteController, itemExtent: 36, onSelectedItemChanged: (value) => selectedMinute = value, children: List.generate(60, (i) => Center(child: Text(i.toString().padLeft(2, '0'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white))))))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text("취소", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.of(context).pop(TimeOfDay(hour: selectedHour, minute: selectedMinute)), child: Text("확인", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).primaryColor))),
        ],
      ),
    );

    hourController.dispose(); minuteController.dispose();
    if (picked == null) return;
    setState(() {
      _timeCon.text = _formatTime24(picked);
      _useFormDriveTimeOnSave = true;
      _dateCon.text = WorkDateUtils.resolveDriveDateForNightShift(_workDateCon.text, _timeCon.text);
      _syncWorkDateFromDriveDateTime();
    });
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

  void _syncWorkDateFromDriveDateTime() {
    final driveDateStr = _dateCon.text.trim();
    final driveTimeStr = _timeCon.text.trim();
    if (driveDateStr.isEmpty || driveTimeStr.isEmpty) return;
    
    final dDate = DateTime.tryParse(driveDateStr);
    if (dDate == null) return;
    
    final hour = WorkDateUtils.hourFromHm(driveTimeStr);
    final String workDateStr;
    if (hour < WorkDateUtils.workDayRolloverHour) {
      final workDate = dDate.subtract(const Duration(days: 1));
      workDateStr = DateFormat('yyyy-MM-dd').format(workDate);
    } else {
      workDateStr = driveDateStr;
    }
    
    setState(() {
      _workDateCon.text = workDateStr;
    });
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<DateTime?> _pickDateFromMonthlyScroller({
    required DateTime initialDate,
    required String title,
  }) async {
    final now = DateTime.now();
    final today = _dayOnly(now);
    final firstOfMonth = DateTime(today.year, today.month, 1);
    final maxDate = today.add(const Duration(days: 1));
    final dates = <DateTime>[];
    var cursor = maxDate;
    while (!cursor.isBefore(firstOfMonth)) {
      dates.add(cursor);
      cursor = cursor.subtract(const Duration(days: 1));
    }

    DateTime selected = _dayOnly(initialDate);
    if (selected.isBefore(firstOfMonth)) selected = firstOfMonth;
    if (selected.isAfter(maxDate)) selected = maxDate;

    final picked = await AppBottomSheet.show<DateTime>(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color!,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final selectedIndex = dates.indexWhere((d) => d == selected);
            return SizedBox(
              height: ResponsiveLayout.bottomSheetHeight(ctx),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white))),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.chevron_left, color: Color(0xFFFFC700)),
                          onPressed: () {
                            final prev = selected.subtract(const Duration(days: 1));
                            if (prev.isBefore(firstOfMonth)) return;
                            setModalState(() => selected = prev);
                          },
                        ),
                        Text(
                          DateFormat('yyyy-MM-dd').format(selected),
                          style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right, color: Color(0xFFFFC700)),
                          onPressed: () {
                            final next = selected.add(const Duration(days: 1));
                            if (next.isAfter(maxDate)) return;
                            setModalState(() => selected = next);
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.12), height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: dates.length,
                      itemBuilder: (ctx, i) {
                        final d = dates[i];
                        final isSelected = i == selectedIndex;
                        return ListTile(
                          title: Text(
                            DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(d),
                            style: TextStyle(
                              color: isSelected ? Theme.of(context).primaryColor : (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                            ),
                          ),
                          onTap: () => setModalState(() => selected = d),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('취소', style: TextStyle(color: Color(0xFF9FA3AE))),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, selected),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.black,
                            ),
                            child: Text('확인'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    return picked;
  }

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
    if (!kMapFeaturesEnabled) return;
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
    if (!kMapFeaturesEnabled) return;
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
    if (!kMapFeaturesEnabled) return const SizedBox.shrink();
    
    // 신규 작성(사진/수동 등) 시에는 숨기고, 수정 모드일 때만 노출
    final bool isEditMode = widget.existingLog != null;
    if (!isEditMode) return const SizedBox.shrink();

    final has = forStart
        ? _startLat != null && _startLng != null
        : _endLat != null && _endLng != null;

    return IconButton(
      icon: Icon(
        has ? Icons.edit_location_alt : Icons.add_location_alt,
        color: has ? const Color(0xFF4CAF50) : Theme.of(context).primaryColor,
        size: 22,
      ),
      onPressed: forStart ? _openStartMapPicker : _openEndMapPicker,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      tooltip: forStart ? (has ? '출발 좌표 수정' : '출발 좌표 등록') : (has ? '도착 좌표 수정' : '도착 좌표 등록'),
    );
  }

  void _onTransportFocusChanged() {
    if (!_transportFocusNode.hasFocus) {
      _appendMemoFromField(
        category: _selectedExpenseCategory,
        amountStr: _transportCon.text,
      );
    }
  }

  void _onWaypointTipFocusChanged() {
    if (!_waypointTipFocusNode.hasFocus) {
      _appendMemoFromField(
        category: _selectedExtraIncomeCategory,
        amountStr: _waypointTipCon.text,
      );
    }
  }

  String _formatToKValue(int amount) {
    if (amount <= 0) return '';
    if (amount % 1000 == 0) {
      return '${amount ~/ 1000}k';
    } else {
      final double kValue = amount / 1000;
      return '${kValue.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), "")}k';
    }
  }

  void _appendMemoFromField({required String category, required String amountStr}) {
    final int amount = _parseMoney(amountStr);
    if (amount <= 0) return;

    final String kStr = _formatToKValue(amount);
    final String appendText = "$category $kStr";

    String currentMemo = _memoCon.text.trim();

    // Prevent duplicate entries of the same category + amount in the memo
    final escaped = RegExp.escape(appendText);
    final hasPattern = RegExp('(?:^|\\s|,)$escaped(?:\$|\\s|,)').hasMatch(currentMemo);
    if (hasPattern) return;

    setState(() {
      if (currentMemo.isEmpty) {
        _memoCon.text = appendText;
      } else {
        if (currentMemo.endsWith(',')) {
          _memoCon.text = "$currentMemo $appendText";
        } else {
          _memoCon.text = "$currentMemo, $appendText";
        }
      }
    });
  }

  /// 저장된 선택값이 현재 설정 목록에 없으면 첫 번째 항목으로 보정
  String _safeExpenseCategory() {
    final list = SettingsService.expenseList.isNotEmpty ? SettingsService.expenseList : ['기타'];
    return list.contains(_selectedExpenseCategory) ? _selectedExpenseCategory : list.first;
  }

  String _safeIncomeCategory() {
    final list = SettingsService.incomeList.isNotEmpty ? SettingsService.incomeList : ['기타'];
    return list.contains(_selectedExtraIncomeCategory) ? _selectedExtraIncomeCategory : list.first;
  }

  int _parseMoney(String value) => int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  String _formatMoney(int value) => NumberFormat('#,###').format(value);
  String? _normalizeYmdForStorage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final normalized = t.replaceAll('.', '-').replaceAll('/', '-');
    try {
      final d = DateFormat('yyyy-MM-dd').parseStrict(normalized);
      return DateFormat('yyyy-MM-dd').format(d);
    } catch (_) {
      return null;
    }
  }
  
  int _currentFeeFromGross() => SettingsService.deductionFeeFromGross(_grossIncome, _selectedProgram);
  int _currentInsuranceFee() => SettingsService.calculatePerTripInsurance(_selectedProgram);
  
  /// 경유비(팁)는 수수료·교통비처럼 차감이 아니라 순익에 **가산**됩니다.
  int _currentNetIncomeFromGross() => (_grossIncome - _currentFeeFromGross() - _currentInsuranceFee() - _parseMoney(_transportCon.text) + _parseMoney(_waypointTipCon.text)).clamp(0, 999999999);

  void _captureGrossAndApplyDeductions() { _grossIncome = _parseMoney(_incomeCon.text); _applyDeductions(); }
  void _applyDeductions() {
    _grossIncome = _parseMoney(_incomeCon.text);
    final int transport = _parseMoney(_transportCon.text);
    final int waypointTip = _parseMoney(_waypointTipCon.text);
    final int fee = _currentFeeFromGross();
    final int insurance = _currentInsuranceFee();
    final int net = (_grossIncome - fee - insurance - transport + waypointTip).clamp(0, 999999999);
    final int deductOnly = fee + insurance + transport;
    setState(() {
      _deductionHint = _grossIncome > 0
          ? "순익 ${_formatMoney(net)}원 (차감 ${_formatMoney(deductOnly)}원)"
          : "";
    });
  }

  bool _validateRequiredManualEntryFields() {
    final missing = <String>[];
    if (_parseMoney(_incomeCon.text) <= 0) missing.add('요금');
    if (_startLocCon.text.trim().isEmpty) missing.add('출발지');
    if (_endLocCon.text.trim().isEmpty) missing.add('도착지');
    if (missing.isEmpty) return true;

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${missing.join('·')}를 입력해 주세요.')),
    );
    return false;
  }

  Future<void> _saveDriveLog() async {
    if (_workDateCon.text.trim().isEmpty || _dateCon.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("근무일자·운행 날짜를 확인해 주세요.")));
      return;
    }
    if (!_validateRequiredManualEntryFields()) return;

    final fare = _parseMoney(_incomeCon.text);
    if (_selectedProgram.contains('카카오') && fare < 12000) {
      if (!mounted) return;
      final bool proceed = await AppGlassDialog.show<bool>(
        context: context,
        barrierDismissible: false,
        dialog: AppGlassDialog(
          icon: Icons.warning_amber_rounded,
          title: '알림',
          content: '입력된 요금이 너무 낮습니다. 계속 진행하시겠습니까?',
          actions: [
            Builder(
              builder: (ctx) => GlassDialogCancelButton(
                label: '아니오',
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ),
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('예', style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ) ?? false;
      if (!proceed) return;
    }

    try {
      if (!mounted) return;

      final workDate = _normalizeYmdForStorage(_workDateCon.text);
      final formDriveDate = _normalizeYmdForStorage(_dateCon.text);
      if (workDate == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("근무일자 형식을 확인해 주세요. (yyyy-MM-dd)")),
        );
        return;
      }
      if (formDriveDate == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("운행일자 형식을 확인해 주세요. (yyyy-MM-dd)")),
        );
        return;
      }

      final String driveTimeForRow = (_logId != null || widget.existingLog != null || _useFormDriveTimeOnSave)
          ? resolveDriveTimeForStorage(_timeCon.text)
          : formatDriveTimeHm(DateTime.now());

      final String driveDateForRow = WorkDateUtils.isDriveHourBeforeWorkDayRollover(driveTimeForRow)
          ? WorkDateUtils.addDays(workDate, 1)
          : formDriveDate;

      if (mounted) {
        setState(() {
          _timeCon.text = driveTimeForRow;
          _dateCon.text = driveDateForRow;
        });
      }

      _grossIncome = _parseMoney(_incomeCon.text);
      final String nowIso = DateTime.now().toIso8601String();
      final compactImagePath = await ImageStorageService.compressAndPersistForDisplay(
        _capturedImage?.path,
        prefix: 'manual',
      );

      final Map<String, dynamic> row = {
        if (_logId != null) "id": _logId,
        "work_date": workDate,
        "drive_date": driveDateForRow,
        "drive_time": resolveDriveTimeForStorage(driveTimeForRow),
        "program": _selectedProgram,
        "gross_fare": _grossIncome, "fee": _currentFeeFromGross(), "insurance_fee": _currentInsuranceFee(), "transport_cost": _parseMoney(_transportCon.text),
        "expense_category": _parseMoney(_transportCon.text) > 0 ? _safeExpenseCategory() : null,
        "waypoint_tip": _parseMoney(_waypointTipCon.text),
        "income_category": _parseMoney(_waypointTipCon.text) > 0 ? _safeIncomeCategory() : null,
        "net_income": _currentNetIncomeFromGross(), "start_location": _startLocCon.text.trim(),
        "waypoint": _waypointCon.text.trim(), "end_location": _endLocCon.text.trim(), "memo": _memoCon.text.trim(),
        "start_lat": _startLat,
        "start_lng": _startLng,
        "end_lat": _endLat,
        "end_lng": _endLng,
        "image_path": compactImagePath,
        "updated_at": nowIso,
        if (_persistedRegistrationSource != null && _persistedRegistrationSource!.trim().isNotEmpty)
          "registration_source": _persistedRegistrationSource!.trim(),
        if (_logId == null)
          "created_at": nowIso
        else if (widget.existingLog != null && widget.existingLog!['created_at'] != null)
          "created_at": widget.existingLog!['created_at'].toString(),
      };

      await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
    } catch (e, st) {
      debugPrint('write_log save error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 중 오류가 발생했습니다: $e")),
      );
      return;
    }

    // 저장 성공 후 처리
    if (!mounted) return;

    final String workStr = _workDateCon.text.trim();
    
    // [자동출근] 미출근 상태 && 입력한 근무일자가 오늘(현재 유효 근무일자)인 경우, 이 일지의 운행시간으로 소급 출근
    // 퇴근 후 시간이 다시 카운트되지 않도록 자동출근 로직 비활성화
    /*
    final timerProvider = Provider.of<WorkTimerProvider>(context, listen: false);
    if (!timerProvider.isClockedIn && workStr == WorkDateUtils.effectiveWorkDateYmd()) {
      final String driveDate = _dateCon.text.trim();
      final String driveTime = _timeCon.text.trim();
      if (driveDate.isNotEmpty && driveTime.isNotEmpty) {
        DateTime? parsedTime = DateTime.tryParse('$driveDate $driveTime:00');
        if (parsedTime != null) {
          if (parsedTime.isAfter(DateTime.now())) {
            parsedTime = DateTime.now(); // 미래 시간 방어 로직
          }
          timerProvider.clockInWithStartTime(parsedTime);
        }
      }
    }
    */

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
          dateTitle: workStr,
          snackMessage: savedMsg,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _onGuideRequested() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    if (guideProvider.pendingGuideTarget == 'write') {
      _startGuideWhenReady();
    }
  }

  void _startGuideWhenReady() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _showWriteGuide();
  }

  void _showWriteGuide() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.clearGuide();

    List<TargetFocus> targets = [];
    
    if (_keyOcrBtn.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "write_ocr_btn",
          keyTarget: _keyOcrBtn,
          color: Colors.black,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "콜카드 이미지 자동 인식",
                  description: "콜카드 캡처본을 첨부하면 내용이 자동으로 입력됩니다!\n\n(단, 화질이나 화면 잘림 등에 의해 간혹 잘못된 값으로 인식될 수 있으니 저장 전에 값이 정확한지 꼭 한 번 더 확인해 주세요.)",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }
    
    if (_keyTimeSection.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "write_time",
          keyTarget: _keyTimeSection,
          color: Colors.black,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "일자 및 시각 변경",
                  description: "운행 일자와 시간을 터치하여 언제든지 변경할 수 있습니다. (콜카드를 첨부하면 캡처된 시간으로 자동 셋팅됩니다.)",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keyFinanceSection.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "write_finance",
          keyTarget: _keyFinanceSection,
          color: Colors.black,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "상세 수입 및 지출",
                  description: "총 운행 요금을 입력하면 수수료가 자동 계산됩니다. 경유 팁이나 복귀 시 사용한 이동 수단 비용도 추가할 수 있어요.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keyLocationSection.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "write_location",
          keyTarget: _keyLocationSection,
          color: Colors.black,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "운행 구간 입력",
                  description: "출발지와 도착지를 입력하세요. 우측의 '+경유지' 버튼을 누르면 경유지도 추가로 입력할 수 있습니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keyMemoSection.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "write_memo",
          keyTarget: _keyMemoSection,
          color: Colors.black,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "메모 및 특이사항",
                  description: "대리기사님이 기록하고 싶은 특이사항이나 메모를 자유롭게 남길 수 있는 공간입니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keySaveBtn.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "write_save",
          keyTarget: _keySaveBtn,
          color: Colors.black,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "일지 저장",
                  description: "모든 내용을 확인한 뒤 버튼을 누르면 일지 작성이 완료됩니다!",
                  controller: controller,
                  isLast: true,
                );
              },
            ),
          ],
        ),
      );
    }

    if (targets.isEmpty) return;

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "건너뛰기",
      paddingFocus: 10,
      opacityShadow: 0.8,
      beforeFocus: (target) async {
        if (target.keyTarget?.currentContext != null) {
          try {
            await Scrollable.ensureVisible(
              target.keyTarget!.currentContext!,
              duration: const Duration(milliseconds: 300),
              alignment: 0.5,
            );
            // wait a little bit for the scroll animation to finish
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            // ignore if not scrollable
          }
        }
      },
    ).show(context: context);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTablet = ResponsiveLayout.isTablet(context);
    final isExpanded = ResponsiveLayout.isExpanded(context);
    final horizontalPadding = ResponsiveLayout.horizontalPadding(context);
    final formMaxW = ResponsiveLayout.formMaxWidth(size);
    final verticalPadding = isTablet ? 12.0 : 10.0;
    final iconSize = isTablet ? 26 : 24;

    final form = Padding(
      padding: EdgeInsets.only(
        left: horizontalPadding,
        right: horizontalPadding,
        top: widget.quickPanel ? (isTablet ? 24.0 : 20.0) : verticalPadding,
        bottom: verticalPadding,
      ),
      child: widget.quickPanel ? _buildQuickPanelFormLayout() : _buildFormLayout(),
    );

    if (widget.quickPanel) {
      // [원복] quickUiOpacity / Opacity 래퍼 제거
      // 투명도 설정 기능 추가 시 Opacity 위젯이 Scaffold 전체를 감싸면서
      // 배경 블러 + 버튼 터치 이벤트 흡수 버그 발생.
      // 배경 투명도는 Scaffold의 backgroundColor(0xCC000000)으로 고정 유지.
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

      final footer = SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            isTablet ? 12.0 : 8.0,
            isTablet ? 8.0 : 6.0,
            isTablet ? 12.0 : 8.0,
            isTablet ? 10.0 : 8.0,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? const Color(0xFF1F222A),
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: closeQuickPanel,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Color(0xFF6E717C)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 10),
                  ),
                  child: Text('닫기', style: TextStyle(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7), fontWeight: FontWeight.w700)),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveDriveLog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 10),
                  ),
                  child: Text('등록', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );

      // [원복] Opacity 래퍼 제거 → Scaffold 직접 반환
      // 기존: return Opacity(opacity: quickUiOpacity, child: Scaffold(...))
      return Scaffold(
        backgroundColor: const Color(0xCC000000), // 80% 불투명 검정 — 기존 반투명 UI 유지
        body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 36.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(formMaxW, size.width * 0.94),
                    maxHeight: size.height * 0.88,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      // 오버레이 컨텍스트는 ThemeData가 단순하여 scaffoldBackgroundColor가
                      // Colors.transparent일 수 있으므로, cardTheme.color 우선 사용
                      color: Theme.of(context).cardTheme.color ?? const Color(0xFF1F222A),
                      child: Column(
                        children: [
                          Expanded(child: form),
                          footer,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardTheme.color!,
        centerTitle: true,
        leading: _logId != null || widget.initialDate != null
          ? IconButton(icon: Icon(Icons.arrow_back, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white), size: iconSize.toDouble()), onPressed: () => Navigator.pop(context)) 
          : null,
        title: Text(
          _logId != null ? '운행 일지 수정' : '운행 일지 작성',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_persistedRegistrationSource != null && _persistedRegistrationSource!.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: isTablet ? 4.0 : 2.0),
              child: Center(child: DriveLogSourceChip(registrationSource: _persistedRegistrationSource)),
            ),
          Padding(
            padding: EdgeInsets.only(right: isTablet ? 12.0 : 8.0),
            child: TextButton(
              key: _keySaveBtn,
              onPressed: _saveDriveLog, 
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
              ),
              child: Text(_logId != null ? "수정" : "등록", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold))
            ),
          )
        ],
      ),
      body: ResponsiveBody(
        fullWidthWhenExpanded: true,
        maxWidth: isExpanded ? size.width : formMaxW,
        child: form,
      ),
    );
  }

  /// 퀵 패널: 요금 · 출발 · 도착 (+경유). 일자·시간·프로그램은 초기값·설정값으로 저장 시 사용.
  Widget _buildQuickPanelFormLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputGroup("요금", Icons.payments_outlined, [
            Row(
              children: [
                Expanded(child: _buildDropdown(bottomMargin: 0)),
                SizedBox(width: 12),
                Expanded(
                  child: _buildInputField(
                    _incomeCon,
                    label: "요금",
                    isNumber: true,
                    bottomMargin: 0,
                    onChanged: (_) {
                      _captureGrossAndApplyDeductions();
                      _applyDeductions();
                    },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
                  icon: Icon(Icons.image, color: Color(0xFFFFC700)),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).primaryColor, width: 2.0),
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
                icon: Icon(Icons.style, color: Color(0xFFFFC700)),
                onPressed: _openGallery,
              ),
            ],
          )),
          SizedBox(height: 14),
          _buildInputGroup("운행 경로", Icons.directions, [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("출발지", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
                    ),
                    SizedBox(width: 8),
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
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _startLocCon,
                  focusNode: _startLocFocusNode,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Color(0xFFFFC700))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: kMapFeaturesEnabled ? _pinPickButton(forStart: true) : null,
                  ),
                ),
                SizedBox(height: 16),
              ],
            ),
            if (_showWaypointField) _buildInputField(_waypointCon, label: "경유지", focusNode: _waypointFocusNode),
            _buildInputField(_endLocCon, label: "도착지", focusNode: _endLocFocusNode, suffixIcon: kMapFeaturesEnabled ? _pinPickButton(forStart: false) : null),
          ]),
        ],
      ),
    );
  }

  Widget _buildDateTimeSection() {
    return Container(
      key: _keyTimeSection,
      child: _buildInputGroup("근무·운행 일자 및 시간", Icons.access_time_filled, [
        if (_logId != null) ...[
        _buildInputField(_workDateCon, label: "근무 일자", readOnly: true, onTap: _showWorkDateQuickPicker),
      ],
      Row(
        children: [
          Expanded(child: _buildInputField(_dateCon, label: "운행 일자", readOnly: true, onTap: _showDateQuickPicker, bottomMargin: 0)),
          SizedBox(width: 12),
          Expanded(child: _buildInputField(_timeCon, label: "운행 시간", readOnly: true, onTap: _showTimeQuickPicker, bottomMargin: 0)),
        ],
      ),
    ]));
  }

  Widget _buildProgramMoneySection() {
    return Container(
      key: _keyFinanceSection,
      child: _buildInputGroup(
            "프로그램 및 금액", Icons.account_balance_wallet, 
            [
              Row(
                children: [
                  Expanded(child: _buildDropdown(bottomMargin: 0)),
                  SizedBox(width: 12),
                  Expanded(child: _buildInputField(_incomeCon, label: "운행 요금", isNumber: true, bottomMargin: 0, focusNode: _incomeFocusNode, onChanged: (_) => _captureGrossAndApplyDeductions())),
                ],
              ),
              SizedBox(height: 16),
              _buildComboInputField(
                _transportCon,
                label: "지출",
                selectedValue: _safeExpenseCategory(),
                dropdownItems: SettingsService.expenseList.isNotEmpty
                    ? SettingsService.expenseList
                    : ['기타'],
                focusNode: _transportFocusNode,
                isNumber: true,
                onDropdownChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedExpenseCategory = value);
                  }
                },
                onChanged: (_) => _applyDeductions(),
              ),
              _buildComboInputField(
                _waypointTipCon,
                label: "수익",
                selectedValue: _safeIncomeCategory(),
                dropdownItems: SettingsService.incomeList.isNotEmpty
                    ? SettingsService.incomeList
                    : ['기타'],
                focusNode: _waypointTipFocusNode,
                isNumber: true,
                onDropdownChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedExtraIncomeCategory = value);
                  }
                },
                onChanged: (_) => _applyDeductions(),
              ),
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_capturedImage != null)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                    icon: Icon(Icons.image, color: Color(0xFFFFC700)),
                    onPressed: () => showDialog(
                      context: context, 
                      builder: (_) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context), 
                          child: Container(
                            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).primaryColor, width: 2.0)),
                            child: Image.file(_capturedImage!)
                          )
                        )
                      )
                    ),
                  ),
                IconButton(
                  key: _keyOcrBtn,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  icon: Icon(Icons.style, color: Color(0xFFFFC700)),
                  onPressed: _openGallery,
                ),
              ],
            ),
          ));
  }

  Widget _buildRouteSection() {
    return Container(
      key: _keyLocationSection,
      child: _buildInputGroup("운행 경로", Icons.directions, [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("출발지", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
                    ),
                    SizedBox(width: 8),
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
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _startLocCon,
                  focusNode: _startLocFocusNode,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Color(0xFFFFC700))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: kMapFeaturesEnabled ? _pinPickButton(forStart: true) : null,
                  ),
                ),
                SizedBox(height: 16),
              ],
            ),
            if (_showWaypointField) _buildInputField(_waypointCon, label: "경유지", focusNode: _waypointFocusNode),
            _buildInputField(
              _endLocCon,
              label: "도착지",
              focusNode: _endLocFocusNode,
              suffixIcon: kMapFeaturesEnabled ? _pinPickButton(forStart: false) : null,
            ),
          ],
            trailing: kMapFeaturesEnabled
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                    icon: Icon(Icons.map, color: Color(0xFFFFC700)),
                    onPressed: _openNaverMapRoute,
                  )
                : null,
          ));
  }

  Widget _buildMemoSection() {
    return Container(
      key: _keyMemoSection,
      child: _buildInputGroup("메모", Icons.note, [_buildInputField(_memoCon, label: "특이사항", maxLines: 3, focusNode: _memoFocusNode)]),
    );
  }

  Widget _buildFormLayout() {
    const gap = 20.0;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    if (ResponsiveLayout.isExpanded(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPad),
              child: Column(
                children: [
                  _buildDateTimeSection(),
                  SizedBox(height: gap),
                  _buildProgramMoneySection(),
                ],
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomPad),
              child: Column(
                children: [
                  _buildRouteSection(),
                  SizedBox(height: gap),
                  _buildMemoSection(),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        children: [
          _buildDateTimeSection(),
          SizedBox(height: gap),
          _buildProgramMoneySection(),
          SizedBox(height: gap),
          _buildRouteSection(),
          SizedBox(height: gap),
          _buildMemoSection(),
        ],
      ),
    );
  }

  Widget _buildInputGroup(String title, IconData icon, List<Widget> children, {Widget? trailing}) {
    return Container(
      decoration: BorderedSection.decoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).primaryColor, size: 20),
                SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontFamily: 'GmarketSans',
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (title == "프로그램 및 금액") ...[
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: _showOcrHelpDialog,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.help_outline,
                        color: Color(0xFFFFC700),
                        size: 14,
                      ),
                    ),
                  ),
                ],
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

  Widget _buildInputField(TextEditingController controller, {required String label, bool isNumber = false, VoidCallback? onTap, bool readOnly = false, double bottomMargin = 16, int maxLines = 1, FocusNode? focusNode, Widget? suffixWidget, Widget? suffixIcon, Function(String)? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          textAlign: isNumber ? TextAlign.right : TextAlign.left,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          inputFormatters: isNumber ? [thousandSeparatorFormatter] : null,
          maxLines: maxLines,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
          decoration: InputDecoration(
            suffix: suffixWidget,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Color(0xFFFFC700))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        SizedBox(height: bottomMargin),
      ],
    );
  }

  Widget _buildComboInputField(
    TextEditingController controller, {
    required String label,
    required String selectedValue,
    required List<String> dropdownItems,
    required ValueChanged<String?> onDropdownChanged,
    FocusNode? focusNode,
    bool isNumber = false,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey))),
        SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: dropdownItems.contains(selectedValue) ? selectedValue : dropdownItems.first,
                    dropdownColor: Theme.of(context).cardTheme.color!,
                    icon: Icon(Icons.arrow_drop_down, color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withOpacity(0.7)),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                    onChanged: onDropdownChanged,
                    items: dropdownItems.map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  textAlign: isNumber ? TextAlign.right : TextAlign.left,
                  keyboardType: isNumber ? TextInputType.number : TextInputType.text,
                  inputFormatters: isNumber ? [thousandSeparatorFormatter] : null,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Color(0xFFFFC700))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDropdown({double bottomMargin = 16}) {
    final options = SettingsService.programList;
    final selected = options.contains(_selectedProgram)
        ? _selectedProgram
        : (options.isNotEmpty ? options.first : _selectedProgram);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("프로그램", style: TextStyle(color: Color(0xFF6E717C), fontSize: 12)),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              dropdownColor: Theme.of(context).cardTheme.color!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
              items: options.map((program) {
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
        if (bottomMargin > 0) SizedBox(height: bottomMargin),
      ],
    );
  }

  void _showOcrHelpDialog() {
    AppGlassDialog.show<void>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.info_outline,
        title: '콜카드 인식 시 주의사항',
        contentWidget: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOcrHelpItem("1", "운행 시간 자동 설정",
                "캡처 이미지 파일이 생성된(캡처된) 시간을 기준으로 운행 시간이 자동으로 셋팅됩니다. (별도로 상단 상태바 시간이 찍히지 않아도 무방합니다.)",
                Icons.access_time),
            SizedBox(height: 12),
            _buildOcrHelpItem("2", "로지 앱 캡처 범위",
                "\"요금\" 부분부터 \"도착지\"까지 한 화면에 온전히 캡처되어야 합니다.", Icons.crop_free),
            SizedBox(height: 12),
            _buildOcrHelpItem("3", "콜마너 앱 캡처 범위",
                "\"출발지\" 부분부터 하단 내용까지 누락 없이 캡처되어야 합니다.", Icons.location_on_outlined),
            SizedBox(height: 12),
            _buildOcrHelpItem("4", "미니 팝업/스티커 주의",
                "화면에 최소화된 플로팅 팝업이나 어플 스티커가 켜져 있으면 인식이 차단되거나 방해받을 수 있습니다.",
                Icons.warning_amber_rounded),
            SizedBox(height: 12),
            _buildOcrHelpItem("5", "인식 결과 확인",
                "자동 인식은 콜카드 이미지의 문구를 읽어내어 자동 셋팅하는 방식이므로, 화면의 화질이나 폰트에 따라 간혹 잘못된 인식값이 나올 수 있습니다. 등록 전 반드시 금액과 주소가 정확한지 확인해 주세요.",
                Icons.rule),
          ],
        ),
        actions: [
          Builder(builder: (ctx) => GlassDialogConfirmButton(filled: true, onPressed: () => Navigator.pop(ctx))),
        ],
      ),
    );
  }

  Widget _buildOcrHelpItem(String step, String title, String desc, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white).withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 16),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$step. $title",
                  style: TextStyle(
                    color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    color: Color(0xFF8A8D96),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _coerceProgramForSelection(String? raw) {
    final options = SettingsService.programList;
    if (options.isEmpty) return raw?.trim().isNotEmpty == true ? raw!.trim() : '기타';
    final input = (raw ?? '').trim();
    if (input.isEmpty) return options.first;
    if (options.contains(input)) return input;
    if (input == KakaoCallCardOcr.programAlliance) {
      for (final option in options) {
        if (option.contains('제휴')) return option;
      }
    }
    if (input == '카카오' ||
        input == KakaoCallCardOcr.programGeneral ||
        input == KakaoCallCardOcr.programPro ||
        input == KakaoCallCardOcr.programAlliance ||
        input == KakaoCustomCallOcr.programCustom) {
      if (options.contains(input)) return input;
      for (final option in options) {
        if (option.contains('카카오')) return option;
      }
    }
    if (input == '티맵') {
      for (final option in options) {
        if (option.contains('티맵')) return option;
      }
    }
    return options.first;
  }
}

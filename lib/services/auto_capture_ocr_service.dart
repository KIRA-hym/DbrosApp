import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/drive_time_format.dart';
import '../utils/work_date_utils.dart';
import '../utils/tmap_trip_detail_ocr.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/logi_colmanner_ocr.dart';
import 'gemini_api_service.dart';
import 'db_helper.dart';
import 'settings_service.dart';
import 'today_stats_notification_service.dart';
import 'ocr_parse_log_service.dart';

class AutoCaptureOcrService {
  AutoCaptureOcrService._();
  static final AutoCaptureOcrService instance = AutoCaptureOcrService._();

  static const MethodChannel _androidChannel = MethodChannel('dbros.app/today_summary');

  bool _busy = false;
  bool _stateLoaded = false;
  String _lastProcessedCaptureKey = '';

  static const String _prefsKeyLastProcessedCapture = 'auto_ocr_last_processed_capture_key';

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 기능 켤 때 최신 스크린샷 1회 확인. 이후에는 [onMediaStoreImagesChanged]만 사용.
  void start() {
    if (!_isAndroid) return;
    Future<void>.microtask(() => _pollLatestScreenshot());
  }

  void stop() {}

  /// Android [MediaStore] 이미지 변경 시 네이티브 [ContentObserver]에서 호출.
  void onMediaStoreImagesChanged() {
    if (!_isAndroid) return;
    Future<void>.microtask(() => _pollLatestScreenshot());
  }

  Future<void> _pollLatestScreenshot() async {
    if (_busy || !SettingsService.statusBarQuickEnabled) return;
    _busy = true;
    try {
      await _ensureStateLoaded();

      final raw = await _androidChannel.invokeMethod<dynamic>('getLatestScreenshot');
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      final path = (map['path'] as String?)?.trim() ?? '';
      final dateAdded = (map['dateAdded'] as num?)?.toInt() ?? 0;
      final imageId = (map['imageId'] as num?)?.toInt() ?? 0;
      // imageId는 항상 > 0. dateAdded는 기기/API에 따라 0일 수 있어 imageId만으로 중복 방지.
      if (path.isEmpty || imageId <= 0) return;
      final captureKey = '${dateAdded}_$imageId';
      if (captureKey == _lastProcessedCaptureKey) return;

      final file = File(path);
      if (!file.existsSync()) return;

      final recognized = await _runOcr(file.path);
      final parsed = await _parseRecognized(recognized);
      final program = (parsed['program'] ?? '').trim();
      final waypoint = (parsed['waypoint'] ?? '').trim();
      final ocrLogId = await OcrParseLogService.record(
        source: 'auto_capture',
        program: program.isEmpty ? null : program,
        rawText: recognized.text,
        parsedData: OcrParseLogService.parsedDataFrom(
          departure: (parsed['start'] ?? '').trim(),
          destination: (parsed['end'] ?? '').trim(),
          waypoints: waypoint.isEmpty ? const <String>[] : [waypoint],
          feeAmount: int.tryParse((parsed['income'] ?? '').replaceAll(RegExp(r'[^0-9]'), '')),
          driveTime: (parsed['driveTime'] ?? '').trim(),
        ),
        recognized: program.isNotEmpty,
      );
      if (!_isValidForAutoSave(parsed)) {
        await _markProcessed(captureKey);
        return;
      }

      final row = _buildRow(parsed, file.path);
      final insertedId = await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
      if (ocrLogId != null && ocrLogId.isNotEmpty) {
        await OcrParseLogService.attachSavedDriveLog(
          ocrLogId,
          {...row, 'id': insertedId},
        );
      }
      await _markProcessed(captureKey);
      await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> _ensureStateLoaded() async {
    if (_stateLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _lastProcessedCaptureKey = prefs.getString(_prefsKeyLastProcessedCapture) ?? '';
    _stateLoaded = true;
  }

  Future<void> _markProcessed(String captureKey) async {
    _lastProcessedCaptureKey = captureKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyLastProcessedCapture, captureKey);
  }

  Future<RecognizedText> _runOcr(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      return await recognizer.processImage(inputImage);
    } finally {
      await recognizer.close();
    }
  }

  // GEMINI_HYBRID_PARSE_BEGIN
  Future<Map<String, String>> _parseRecognized(RecognizedText recognizedText) async {
    final blocks = List<TextBlock>.from(recognizedText.blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = recognizedText.text;

    var program = _detectProgram(full) ?? '';
    program = KakaoCallCardOcr.refineProgramByAllianceHeuristic(full, blocks, program);

    String nowHm() {
      final n = DateTime.now();
      return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    }

    if (program == '티맵') {
      final r = await TmapTripDetailOcr.tryParse(full, blocks: recognizedText.blocks);
      if (r != null) {
        var timeHm = r.driveStartTimeHm;
        if (timeHm.isEmpty) {
          timeHm = nowHm();
        }
        return {
          'program': '티맵',
          'driveDate':
              r.driveDateYmd.isNotEmpty ? r.driveDateYmd : WorkDateUtils.effectiveWorkDateYmd(),
          'driveTime': timeHm,
          'income': r.grossFare > 0 ? r.grossFare.toString() : '',
          'start': r.startAddress,
          'end': r.endAddress,
          'waypoint': '',
        };
      }
      return {
        'program': '티맵',
        'driveDate': WorkDateUtils.effectiveWorkDateYmd(),
        'driveTime': nowHm(),
        'income': '',
        'start': '',
        'end': '',
        'waypoint': '',
      };
    }

    if (program == KakaoCustomCallOcr.programCustom) {
      final p = await KakaoCustomCallOcr.parseScreen(blocks, full);
      final wd = WorkDateUtils.effectiveWorkDateYmd();
      var driveDate = p.driveDateYmd ?? wd;
      var timeHm = p.driveTimeHm ?? '';
      if (timeHm.isEmpty) {
        timeHm = nowHm();
      }
      return {
        'program': program,
        'driveDate': driveDate,
        'driveTime': timeHm,
        'income': p.grossFare != null && p.grossFare! > 0 ? p.grossFare!.toString() : '',
        'start': p.startLocation,
        'end': p.endLocation,
        'waypoint': '',
        'paymentMethod': p.paymentMethod ?? '',
      };
    }

    if (program == KakaoCallCardOcr.programGeneral ||
        program == KakaoCallCardOcr.programPro ||
        program == KakaoCallCardOcr.programAlliance) {
      final p = await KakaoCallCardOcr.parseScreen(blocks, full, program);
      final wd = WorkDateUtils.effectiveWorkDateYmd();
      var driveDate = p.driveDateYmd ?? wd;
      var timeHm = p.driveTimeHm ?? '';
      if (timeHm.isEmpty) {
        timeHm = nowHm();
      }
      return {
        'program': program,
        'driveDate': driveDate,
        'driveTime': timeHm,
        'income': p.grossFare != null && p.grossFare! > 0 ? p.grossFare!.toString() : '',
        'start': p.startLocation,
        'end': p.endLocation,
        'waypoint': p.waypoint,
      };
    }

    if (program == '로지') {
      final p = await LogiColmannerOcr.parseLogi(full, blocks: blocks);
      final timeHm = p.driveTimeHm.isNotEmpty ? p.driveTimeHm : nowHm();
      return {
        'program': '로지',
        'driveDate': WorkDateUtils.effectiveWorkDateYmd(),
        'driveTime': timeHm,
        'income': p.grossFare > 0 ? p.grossFare.toString() : '',
        'start': p.startLocation,
        'end': p.endLocation,
        'waypoint': p.waypoint,
      };
    }

    if (program == '콜마너') {
      final p = await LogiColmannerOcr.parseColmanner(full, blocks: blocks);
      final timeHm = p.driveTimeHm.isNotEmpty ? p.driveTimeHm : nowHm();
      return {
        'program': '콜마너',
        'driveDate': WorkDateUtils.effectiveWorkDateYmd(),
        'driveTime': timeHm,
        'income': p.grossFare > 0 ? p.grossFare.toString() : '',
        'start': p.startLocation,
        'end': p.endLocation,
        'waypoint': p.waypoint,
      };
    }

    final gProg = program.isEmpty ? '미분류' : program;
    final gem = await GeminiApiService.instance.parseCallCard(fullText: full, detectedProgram: gProg);
    if (gem.usageExceeded || gem.fields == null) {
      return {
        'program': program,
        'driveDate': WorkDateUtils.effectiveWorkDateYmd(),
        'driveTime': nowHm(),
        'income': '',
        'start': '',
        'end': '',
        'waypoint': '',
      };
    }
    final f = gem.fields!;
    var driveDate = WorkDateUtils.effectiveWorkDateYmd();
    final dateMatch = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(full);
    if (dateMatch != null) {
      driveDate =
          '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}';
    }
    final driveTime = f.driveTimeHm.isEmpty
        ? nowHm()
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    return {
      'program': program.isEmpty ? gProg : program,
      'driveDate': driveDate,
      'driveTime': driveTime,
      'income': f.grossFare > 0 ? f.grossFare.toString() : '',
      'start': f.startLocation,
      'end': f.endLocation,
      'waypoint': f.waypoint,
    };
  }
  // GEMINI_HYBRID_PARSE_END

  String? _detectProgram(String fullText) {
    final normalized = fullText.replaceAll(' ', '');
    if (KakaoCustomCallOcr.isCustomCallScreen(fullText)) {
      return KakaoCustomCallOcr.programCustom;
    }
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) return kakao;
    if (normalized.contains('고객과통화') ||
        normalized.contains('카카오T') ||
        normalized.contains('카카오')) {
      return KakaoCallCardOcr.programGeneral;
    }
    if (normalized.contains('오더번호') ||
        normalized.contains('고객ID') ||
        normalized.contains('로지')) {
      return '로지';
    }
    if (normalized.contains('운행시작') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지') &&
        (normalized.contains('입금액') || normalized.contains('고객과의거리'))) {
      return '로지';
    }
    if (normalized.contains('출도') ||
        normalized.contains('콜마너') ||
        normalized.contains('콜매니저')) {
      return '콜마너';
    }
    if (normalized.contains('지사명') &&
        normalized.contains('출도') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지')) {
      return '콜마너';
    }
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) return '티맵';
    return null;
  }

  bool _isValidForAutoSave(Map<String, String> parsed) {
    final income = int.tryParse(parsed['income'] ?? '') ?? 0;
    final program = (parsed['program'] ?? '').trim();
    final programDetected = program.contains('카카오') ||
        program == '로지' ||
        program == '콜마너' ||
        program == '티맵';
    return programDetected &&
        income > 0 &&
        (parsed['start'] ?? '').trim().isNotEmpty &&
        (parsed['end'] ?? '').trim().isNotEmpty;
  }

  Map<String, dynamic> _buildRow(Map<String, String> parsed, String imagePath) {
    final nowIso = DateTime.now().toIso8601String();
    /// 콜카드 단건·다중과 동일: 근무일 = 효과 근무일, 운행일 = 새벽 규칙 반영.
    final workDate = WorkDateUtils.effectiveWorkDateYmd();
    final timeStr = resolveDriveTimeForStorage(parsed['driveTime']);
    final driveDate = WorkDateUtils.resolveDriveDateForNightShift(workDate, timeStr);
    final income = int.tryParse(parsed['income'] ?? '') ?? 0;
    final program = parsed['program'] ?? KakaoCallCardOcr.programGeneral;
    final fee = SettingsService.deductionFeeFromGross(income, program);
    final net = (income - fee).clamp(0, 999999999);

    return {
      'work_date': workDate,
      'drive_date': driveDate,
      'drive_time': timeStr,
      'program': program,
      'gross_fare': income,
      'fee': fee,
      'transport_cost': 0,
      'waypoint_tip': 0,
      'net_income': net,
      'start_location': (parsed['start'] ?? '').trim(),
      'waypoint': (parsed['waypoint'] ?? '').trim(),
      'end_location': (parsed['end'] ?? '').trim(),
      'memo': (() {
        final pm = (parsed['paymentMethod'] ?? '').trim();
        if (pm.isEmpty) return '자동등록(OCR)';
        return '자동등록(OCR) 결제:$pm';
      })(),
      'image_path': imagePath,
      'updated_at': nowIso,
      'created_at': nowIso,
    };
  }
}

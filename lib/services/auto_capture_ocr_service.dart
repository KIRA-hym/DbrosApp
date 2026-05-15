import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/drive_time_format.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/work_date_utils.dart';
import 'db_helper.dart';
import 'gemini_api_service.dart';
import 'ocr_parse_log_service.dart';
import 'settings_service.dart';
import 'today_stats_notification_service.dart';

class AutoCaptureOcrService {
  AutoCaptureOcrService._();
  static final AutoCaptureOcrService instance = AutoCaptureOcrService._();

  static const MethodChannel _androidChannel = MethodChannel('dbros.app/today_summary');

  bool _busy = false;
  bool _stateLoaded = false;
  String _lastProcessedCaptureKey = '';

  static const String _prefsKeyLastProcessedCapture = 'auto_ocr_last_processed_capture_key';

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  void start() {
    if (!_isAndroid) return;
    Future<void>.microtask(() => _pollLatestScreenshot());
  }

  void stop() {}

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
      if (path.isEmpty || imageId <= 0) return;
      final captureKey = '${dateAdded}_$imageId';
      if (captureKey == _lastProcessedCaptureKey) return;

      final file = File(path);
      if (!file.existsSync()) return;

      final r = await GeminiApiService.instance.parseCallCardImage(file);
      final fields = r.fields;
      final program = (fields?.program ?? '').trim();

      final ocrLogId = await OcrParseLogService.record(
        source: 'auto_capture',
        program: program.isEmpty ? null : program,
        rawText: '(multimodal)',
        parsedData: OcrParseLogService.parsedDataFrom(
          departure: (fields?.startLocation ?? '').trim(),
          destination: (fields?.endLocation ?? '').trim(),
          waypoints: (fields?.waypoint ?? '').trim().isEmpty
              ? const <String>[]
              : [(fields?.waypoint ?? '').trim()],
          feeAmount: fields?.grossFare,
          driveTime: (fields?.driveTimeHm ?? '').trim(),
        ),
        recognized: program.isNotEmpty,
      );

      if (r.usageExceeded || fields == null) {
        if (ocrLogId != null) {
          /* logged without save */
        }
        await _markProcessed(captureKey);
        return;
      }

      final parsed = _parsedFromGemini(fields, program);
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

  Map<String, String> _parsedFromGemini(GeminiParsedFields f, String program) {
    String nowHm() {
      final n = DateTime.now();
      return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    }

    final t = f.driveTimeHm.isEmpty
        ? nowHm()
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    return {
      'program': program,
      'driveDate': WorkDateUtils.effectiveWorkDateYmd(),
      'driveTime': t,
      'income': f.grossFare > 0 ? f.grossFare.toString() : '',
      'start': f.startLocation,
      'end': f.endLocation,
      'waypoint': f.waypoint,
      'paymentMethod': '',
    };
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
        if (pm.isEmpty) return '자동등록';
        return '자동등록 결제:$pm';
      })(),
      'image_path': imagePath,
      'updated_at': nowIso,
      'created_at': nowIso,
    };
  }
}

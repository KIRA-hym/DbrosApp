import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/drive_time_format.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/logi_colmanner_ocr.dart';
import '../utils/tmap_trip_detail_ocr.dart';
import '../utils/work_date_utils.dart';
import 'db_helper.dart';
import 'image_storage_service.dart';
import 'ocr_parse_log_service.dart';
import 'settings_service.dart';

/// 콜카드 이미지 OCR → 운행일지 row 파싱·저장 (멀티 콜카드·스크린샷 자동등록 공용).
class CallCardOcrParseService {
  CallCardOcrParseService._();

  static Future<Map<String, dynamic>> parseImageFile(
    File imageFile, {
    String? workDateYmd,
    String ocrSource = 'call_card',
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(imageFile.path));
      return parseRecognizedText(
        recognized,
        imageFile,
        workDateYmd: workDateYmd,
        ocrSource: ocrSource,
      );
    } finally {
      await recognizer.close();
    }
  }

  static Future<Map<String, dynamic>> parseRecognizedText(
    RecognizedText recognizedText,
    File imageFile, {
    String? workDateYmd,
    String ocrSource = 'call_card',
  }) async {
    final blocks = List<TextBlock>.from(recognizedText.blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final rawProgram = _detectProgram(blocks, recognizedText.text);
    if (rawProgram == null) {
      await OcrParseLogService.record(
        source: ocrSource,
        rawText: recognizedText.text,
        parsedData: OcrParseLogService.parsedDataFrom(),
        recognized: false,
      );
      return {};
    }

    final detectedProgram = _normalizeProgramForSave(rawProgram);
    final defaultWorkDate = workDateYmd ?? WorkDateUtils.effectiveWorkDateYmd();

    final logData = <String, dynamic>{
      'program': detectedProgram,
      'image_path': imageFile.path,
      'drive_date': defaultWorkDate,
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
    } else if (rawProgram == KakaoCallCardOcr.programGeneral ||
        rawProgram == KakaoCallCardOcr.programPro ||
        rawProgram == KakaoCallCardOcr.programAlliance) {
      await _parseKakao(blocks, logData, fullText: recognizedText.text);
    } else if (rawProgram == '로지') {
      await _parseLogi(blocks, logData);
    } else if (rawProgram == '콜마너') {
      await _parseColmanner(blocks, logData);
    } else if (rawProgram == '티맵') {
      await _parseTmapTripDetail(recognizedText, logData);
    }

    final grossFare = logData['gross_fare'] as int;
    final transportCost = logData['transport_cost'] as int;
    final fee = SettingsService.deductionFeeFromGross(grossFare, detectedProgram);
    final netIncome = (grossFare - fee - transportCost).clamp(0, 999999999);

    logData['fee'] = fee;
    logData['net_income'] = netIncome;

    final ocrLogId = await OcrParseLogService.record(
      source: ocrSource,
      program: detectedProgram,
      rawText: recognizedText.text,
      parsedData: OcrParseLogService.parsedDataFromLogData(logData),
    );
    if (ocrLogId != null) {
      logData['ocr_log_id'] = ocrLogId;
    }

    return logData;
  }

  /// 자동등록: 프로그램 인식 + [write_log] 수동 등록과 동일 필수값(요금·출발지·도착지).
  /// 운행시간 미인식 시 [saveLogToDatabase]에서 현재 시각으로 보정.
  static bool isValidForAutoSave(Map<String, dynamic> logData) {
    if (logData.isEmpty) return false;
    if (!_nonEmptyTrimmed(logData['program'])) return false;
    if (_parsedGrossFare(logData) <= 0) return false;
    if (!_nonEmptyTrimmed(logData['start_location'])) return false;
    if (!_nonEmptyTrimmed(logData['end_location'])) return false;
    return true;
  }

  static bool _nonEmptyTrimmed(dynamic value) => value?.toString().trim().isNotEmpty == true;

  static int _parsedGrossFare(Map<String, dynamic> logData) {
    final gross = logData['gross_fare'];
    if (gross is int) return gross;
    return int.tryParse(gross?.toString() ?? '') ?? 0;
  }

  /// 동일 스크린샷을 다른 경로(gallery 파일 vs 네이티브 캐시)로 두 번 잡았을 때 DB 이중 삽입 방지용.
  static String autoSaveDuplicateFingerprint(Map<String, dynamic> logData) {
    if (!isValidForAutoSave(logData)) return '';
    String norm(String? s) =>
        s?.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final fare = _parsedGrossFare(logData);
    final timePart = hasValidDriveTimeHm(logData['drive_time'])
        ? (normalizeDriveTimeHm(logData['drive_time'].toString()) ?? '')
        : '';
    return [
      norm(logData['program']?.toString()),
      fare.toString(),
      norm(logData['start_location']?.toString()),
      norm(logData['end_location']?.toString()),
      norm(logData['waypoint']?.toString()),
      timePart,
    ].join('\u001f');
  }

  static Future<bool> saveLogToDatabase(
    Map<String, dynamic> logData, {
    String imagePrefix = 'ocr',
    String? workDateYmd,
  }) async {
    if (!isValidForAutoSave(logData)) return false;

    final work = workDateYmd ?? WorkDateUtils.effectiveWorkDateYmd();
    var timeStr = resolveDriveTimeForStorage(logData['drive_time']?.toString());
    if (!hasValidDriveTimeHm(logData['drive_time'])) {
      timeStr = formatDriveTimeHm(DateTime.now());
      logData['drive_time'] = timeStr;
    }
    final drive = WorkDateUtils.resolveDriveDateForNightShift(work, timeStr);
    final nowIso = DateTime.now().toIso8601String();

    final imagePath = await ImageStorageService.compressAndPersistForDisplay(
      logData['image_path']?.toString(),
      prefix: imagePrefix,
    );

    final row = <String, dynamic>{
      'work_date': work,
      'drive_date': drive,
      'drive_time': timeStr,
      'program': logData['program'],
      'gross_fare': logData['gross_fare'],
      'fee': logData['fee'],
      'transport_cost': logData['transport_cost'],
      'net_income': logData['net_income'],
      'start_location': logData['start_location'],
      'waypoint': logData['waypoint'],
      'end_location': logData['end_location'],
      'memo': logData['memo'],
      'image_path': imagePath,
      'created_at': nowIso,
      'updated_at': nowIso,
    };

    final insertedId = await DriveLogDatabase.instance.insertOrUpdateDriveLog(row);
    final ocrLogId = logData['ocr_log_id']?.toString();
    if (ocrLogId != null && ocrLogId.isNotEmpty) {
      await OcrParseLogService.attachSavedDriveLog(
        ocrLogId,
        {...row, 'id': insertedId},
      );
    }
    return true;
  }

  static String? _detectProgram(List<TextBlock> blocks, String fullText) {
    final normalized = fullText.replaceAll(RegExp(r'\s+'), '');
    for (final block in blocks) {
      if (block.text.contains('갱신')) return '로지';
      if (block.text.contains('출도')) return '콜마너';
    }
    if (normalized.contains('운행시작') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지') &&
        (normalized.contains('입금액') || normalized.contains('고객과의거리'))) {
      return '로지';
    }
    if (normalized.contains('지사명') &&
        normalized.contains('출도') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지')) {
      return '콜마너';
    }
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) return '티맵';
    if (KakaoCustomCallOcr.isCustomCallScreen(fullText)) return KakaoCustomCallOcr.programCustom;
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) {
      return KakaoCallCardOcr.refineProgramByAllianceHeuristic(fullText, blocks, kakao);
    }
    for (final block in blocks) {
      if (block.text.contains('고객과 통화')) {
        return KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          fullText,
          blocks,
          KakaoCallCardOcr.programGeneral,
        );
      }
    }
    return null;
  }

  static String _normalizeProgramForSave(String program) {
    if (program == '카카오') return '카카오(일반)';
    if (program == KakaoCallCardOcr.programGeneral ||
        program == KakaoCallCardOcr.programPro ||
        program == KakaoCallCardOcr.programAlliance ||
        program == KakaoCustomCallOcr.programCustom) {
      return program;
    }
    return program;
  }

  static Future<void> _parseKakaoCustom(
    List<TextBlock> blocks,
    Map<String, dynamic> logData, {
    required String fullText,
  }) async {
    final p = KakaoCustomCallOcr.parseScreen(blocks, fullText);
    if (p.driveDateYmd != null) logData['drive_date'] = p.driveDateYmd;
    if (p.driveTimeHm != null) logData['drive_time'] = p.driveTimeHm;
    logData['waypoint'] = '';
    logData['start_location'] = p.startLocation;
    logData['end_location'] = p.endLocation;
    if (p.grossFare != null) logData['gross_fare'] = p.grossFare;
    if ((p.paymentMethod ?? '').isNotEmpty) {
      final prev = (logData['memo'] ?? '').toString().trim();
      final tag = '결제방식:${p.paymentMethod}';
      logData['memo'] = prev.isEmpty ? tag : '$tag $prev';
    }
  }

  static Future<void> _parseKakao(
    List<TextBlock> blocks,
    Map<String, dynamic> logData, {
    required String fullText,
  }) async {
    final p = KakaoCallCardOcr.parseScreen(blocks, fullText);
    if (p.driveDateYmd != null) logData['drive_date'] = p.driveDateYmd;
    if (p.driveTimeHm != null) logData['drive_time'] = p.driveTimeHm;
    logData['waypoint'] = p.waypoint;
    logData['start_location'] = p.startLocation;
    logData['end_location'] = p.endLocation;
    if (p.grossFare != null) logData['gross_fare'] = p.grossFare;
  }

  static Future<void> _parseLogi(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    final sortedBlocks = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sortedBlocks.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseLogi(full, blocks: sortedBlocks);
    if (p.driveTimeHm.isNotEmpty) logData['drive_time'] = p.driveTimeHm;
    if (p.grossFare > 0) logData['gross_fare'] = p.grossFare;
    if (p.startLocation.isNotEmpty) logData['start_location'] = p.startLocation;
    if (p.endLocation.isNotEmpty) logData['end_location'] = p.endLocation;
    if (p.waypoint.isNotEmpty) logData['waypoint'] = p.waypoint;
  }

  static Future<void> _parseColmanner(List<TextBlock> blocks, Map<String, dynamic> logData) async {
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sorted.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseColmanner(full, blocks: sorted);
    if (p.driveTimeHm.isNotEmpty) logData['drive_time'] = p.driveTimeHm;
    if (p.grossFare > 0) logData['gross_fare'] = p.grossFare;
    if (p.startLocation.isNotEmpty) logData['start_location'] = p.startLocation;
    if (p.endLocation.isNotEmpty) logData['end_location'] = p.endLocation;
    if (p.waypoint.isNotEmpty) logData['waypoint'] = p.waypoint;
  }

  static Future<void> _parseTmapTripDetail(
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
    if (r.waypoint != null && r.waypoint!.isNotEmpty) {
      logData['waypoint'] = r.waypoint;
    }
  }
}

import 'package:flutter/foundation.dart';

import 'gemini_ocr_service.dart';
import 'remote_config_service.dart';

/// OCR 파싱 결과 보완 서비스 (기존 코드를 전혀 건드리지 않음).
/// 기존 파서가 파싱한 결과(logData)를 받아 신뢰도를 검사하고,
/// 필요한 경우에만 Gemini API를 호출하여 결과를 보완한다.
///
/// 사용법 (call_card_ocr_parse_service.dart의 return logData; 직전에 1줄 추가):
///   final enhanced = await SmartOcrService.enhance(logData, recognizedText.text);
///   return enhanced;
class SmartOcrService {
  SmartOcrService._();

  /// 기존 파싱 결과를 받아 신뢰도 검사 후 필요 시 Gemini로 보완하여 반환.
  /// 실패 시 항상 원본 [logData]를 그대로 반환 (기존 동작 보장).
  static Future<Map<String, dynamic>> enhance(
    Map<String, dynamic> logData,
    String rawText,
  ) async {
    if (logData.isEmpty) return logData;

    final start = logData['start_location']?.toString() ?? '';
    final end = logData['end_location']?.toString() ?? '';

    // 신뢰도 검사: 두 주소 모두 깨끗하면 Gemini 호출 없이 바로 반환
    if (_isClean(start) && _isClean(end)) {
      if (kDebugMode) print('[SmartOcr] Confidence OK. Skipping Gemini.');
      return logData;
    }

    if (kDebugMode) {
      print('[SmartOcr] Garbage detected. Calling Gemini...');
      print('[SmartOcr] start="$start" end="$end"');
    }

    // Gemini 호출 (한도 초과 또는 오류 시 null 반환)
    final geminiResult = await GeminiOcrService.cleanAndEnhance(
      rawText: rawText,
      parsedData: logData,
    );

    if (geminiResult == null) {
      if (kDebugMode) print('[SmartOcr] Gemini returned null. Using original result.');
      return logData;
    }

    // Gemini 결과로 해당 필드만 덮어쓰기 (나머지 필드는 기존 값 유지)
    final enhanced = Map<String, dynamic>.from(logData);
    _applyIfValid(enhanced, 'start_location', geminiResult['start_location']);
    _applyIfValid(enhanced, 'end_location', geminiResult['end_location']);
    _applyFareIfValid(enhanced, geminiResult['gross_fare']);

    if (kDebugMode) {
      print('[SmartOcr] Enhanced: start="${enhanced['start_location']}" end="${enhanced['end_location']}"');
    }

    return enhanced;
  }

  /// 주소가 가비지 없이 깨끗한지 판단.
  /// Firebase Remote Config의 'ocr_confidence_rules' JSON으로 관리.
  static bool _isClean(String address) {
    if (address.trim().isEmpty) return false;

    // Remote Config에서 금지 단어 목록 가져오기 (없으면 기본값 사용)
    final forbiddenWords = RemoteConfigService().ocrForbiddenWords;
    for (final word in forbiddenWords) {
      if (address.contains(word)) return false;
    }

    // 주소 길이가 비정상적으로 길면 의심
    final maxLen = RemoteConfigService().ocrMaxAddressLength;
    if (address.length > maxLen) return false;

    // 전화번호 패턴 감지 (예: 010-1234-5678)
    if (RegExp(r'\d{3}-\d{3,4}').hasMatch(address)) return false;

    return true;
  }

  static void _applyIfValid(Map<String, dynamic> data, String key, dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      data[key] = value.trim();
    }
  }

  static void _applyFareIfValid(Map<String, dynamic> data, dynamic value) {
    if (value is int && value > 0) {
      data['gross_fare'] = value;
    } else if (value is String) {
      final parsed = int.tryParse(value.replaceAll(',', '').replaceAll('원', '').trim());
      if (parsed != null && parsed > 0) {
        data['gross_fare'] = parsed;
      }
    }
  }
}

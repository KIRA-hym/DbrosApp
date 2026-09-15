import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'firestore_rule_service.dart';

/// Firestore JSON 룰을 기반으로 OCR 텍스트를 파싱하는 동적 엔진
class OcrRuleEngine {
  OcrRuleEngine._();

  /// 룰 엔진을 통해 파싱 시도.
  /// 매칭되는 룰이 없거나 파싱에 실패하면 null 반환 (기존 하드코딩 로직으로 Fallback)
  static Map<String, dynamic>? tryParse(String rawText, List<TextBlock> blocks) {
    final rules = FirestoreRuleService.rules;
    if (rules == null || !rules.containsKey('platforms')) {
      return null; // 룰이 없으면 기존 로직 사용
    }

    // 줄바꿈 공백 등을 정제한 텍스트 (키워드 매칭용)
    final flatText = rawText.replaceAll(RegExp(r'\s+'), ' ');

    final platforms = rules['platforms'] as Map<String, dynamic>;

    for (final entry in platforms.entries) {
      final platformId = entry.key;
      final config = entry.value as Map<String, dynamic>;

      if (_isMatch(flatText, config['detect_keywords'])) {
        if (kDebugMode) print('[OcrRuleEngine] Matched platform rule: $platformId');
        return _executeRule(platformId, config, rawText);
      }
    }

    return null; // 매칭된 룰이 없음
  }

  /// 모든 detect_keywords가 텍스트에 존재하는지 확인
  static bool _isMatch(String text, dynamic keywordsObj) {
    if (keywordsObj == null) return false;
    final keywords = List<String>.from(keywordsObj);
    if (keywords.isEmpty) return false;

    // 정의된 모든 키워드가 포함되어야 해당 플랫폼으로 인정
    for (final kw in keywords) {
      if (!text.contains(kw)) return false;
    }
    return true;
  }

  /// 매칭된 룰을 실행하여 파싱 결과 Map 반환
  static Map<String, dynamic>? _executeRule(
    String platformId,
    Map<String, dynamic> config,
    String rawText,
  ) {
    try {
      // 1. 노이즈 제거
      String processedText = rawText;
      final noiseList = List<String>.from(config['noise_remove'] ?? []);
      for (final noise in noiseList) {
        processedText = processedText.replaceAll(noise, ' ');
      }

      // 2. 정규식 추출
      final patterns = config['field_patterns'] as Map<String, dynamic>? ?? {};
      
      String extract(String key) {
        final pattern = patterns[key]?.toString();
        if (pattern == null || pattern.isEmpty) return '';
        final match = RegExp(pattern).firstMatch(processedText);
        return match != null && match.groupCount >= 1 ? (match.group(1) ?? '').trim() : '';
      }

      final grossFareStr = extract('gross_fare').replaceAll(RegExp(r'[^0-9]'), '');
      final grossFare = int.tryParse(grossFareStr) ?? 0;

      // 3. 결과 포맷팅 (CallCardOcrParseService의 logData 형식과 동일하게 맞춤)
      return {
        'program': config['program_name'] ?? platformId,
        'drive_date': extract('drive_date'),
        'drive_time': extract('drive_time'),
        'gross_fare': grossFare,
        'transport_cost': 0, // 기본값
        'start_location': extract('start_location'),
        'waypoint': extract('waypoint'),
        'end_location': extract('end_location'),
        'memo': '',
        'raw_text': rawText,
        'parse_engine': 'firestore_json_rule', // 추적용 태그
      };
    } catch (e) {
      if (kDebugMode) print('[OcrRuleEngine] Execution failed for $platformId: $e');
      return null;
    }
  }
}

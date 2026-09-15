import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'remote_config_service.dart';

/// Gemini API 호출 + 일일 무료 한도 관리 서비스.
/// Firebase Remote Config의 'gemini_api_key' 와 'gemini_daily_limit' 값을 사용.
/// Firestore 'gemini_quota/daily' 문서로 전체 앱의 일일 호출 수를 추적.
/// 한도 초과 시 null을 반환하여 비용 0원을 보장.
class GeminiOcrService {
  GeminiOcrService._();

  static const String _firestoreDoc = 'gemini_quota';
  static const String _firestoreDocId = 'daily';
  static const String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  /// OCR 원문 텍스트와 이미 파싱된 결과를 받아 Gemini에게 정제 요청.
  /// 한도 초과 또는 오류 시 null 반환.
  static Future<Map<String, dynamic>?> cleanAndEnhance({
    required String rawText,
    required Map<String, dynamic> parsedData,
  }) async {
    final apiKey = RemoteConfigService().geminiApiKey;
    if (apiKey.isEmpty) {
      if (kDebugMode) print('[GeminiOcr] API key not configured. Skipping.');
      return null;
    }

    final canCall = await _checkAndIncrementQuota();
    if (!canCall) {
      if (kDebugMode) print('[GeminiOcr] Daily limit reached. Skipping.');
      return null;
    }

    try {
      return await _callGemini(apiKey: apiKey, rawText: rawText, parsedData: parsedData);
    } catch (e) {
      if (kDebugMode) print('[GeminiOcr] API call failed: $e');
      return null;
    }
  }

  static Future<bool> _checkAndIncrementQuota() async {
    try {
      final today = _todayString();
      final ref = FirebaseFirestore.instance
          .collection(_firestoreDoc)
          .doc(_firestoreDocId);

      bool allowed = false;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final limit = RemoteConfigService().geminiDailyLimit;

        if (!snapshot.exists || snapshot.data()?['date'] != today) {
          transaction.set(ref, {'date': today, 'count': 1, 'limit': limit});
          allowed = true;
        } else {
          final count = (snapshot.data()?['count'] ?? 0) as int;
          if (count < limit) {
            transaction.update(ref, {'count': count + 1});
            allowed = true;
          } else {
            allowed = false;
          }
        }
      });
      return allowed;
    } catch (e) {
      if (kDebugMode) print('[GeminiOcr] Quota check failed: $e');
      return true;
    }
  }

  static Future<Map<String, dynamic>?> _callGemini({
    required String apiKey,
    required String rawText,
    required Map<String, dynamic> parsedData,
  }) async {
    final start = parsedData['start_location']?.toString() ?? '';
    final end = parsedData['end_location']?.toString() ?? '';
    final fare = parsedData['gross_fare']?.toString() ?? '';

    final prompt = '''
다음은 대리운전 콜카드 OCR 텍스트와 현재 파싱된 결과입니다.
파싱된 결과에서 가비지(노이즈) 단어를 제거하고, 실제 주소만 남겨 JSON으로 반환해 주세요.
파싱 결과가 비어있다면 OCR 원문에서 찾아 채워주세요.
반드시 JSON 형식으로만 응답하세요. 설명 없이 JSON만 반환하세요.

[현재 파싱 결과]
출발지: $start
도착지: $end
요금: $fare

[OCR 원문]
$rawText

[응답 형식]
{"start_location": "정제된 출발지 주소", "end_location": "정제된 도착지 주소", "gross_fare": 숫자}
''';

    final response = await http.post(
      Uri.parse('$_geminiEndpoint?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{'parts': [{'text': prompt}]}],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 200},
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      if (kDebugMode) print('[GeminiOcr] HTTP ${response.statusCode}');
      return null;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text == null || text.isEmpty) return null;

    final cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

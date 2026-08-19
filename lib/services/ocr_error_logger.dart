import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OcrErrorLoggerService {
  static final OcrErrorLoggerService instance = OcrErrorLoggerService._internal();

  OcrErrorLoggerService._internal();

  final Set<String> _sessionSentHashes = {};

  Future<void> logError({
    required String platform,
    required String rawText,
    String? errorReason,
    Map<String, dynamic>? parsedData,
  }) async {
    try {
      final textHash = rawText.hashCode.toString();
      
      // 1. 이번 세션에서 이미 전송한 동일한 텍스트면 무시 (스팸 방지)
      if (_sessionSentHashes.contains(textHash)) {
        return;
      }

      // 2. 확률 기반 샘플링 (30% 확률로 전송)
      if (Random().nextDouble() > 0.3) {
        if (kDebugMode) print('OCR Error Log skipped due to sampling');
        return;
      }

      // 3. 1일 전송 횟수 제한 (3회)
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final countKey = 'ocr_log_count_$todayStr';
      final currentCount = prefs.getInt(countKey) ?? 0;

      if (currentCount >= 3) {
        if (kDebugMode) print('OCR Error Log skipped due to daily quota limit (3)');
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      
      await FirebaseFirestore.instance.collection('ocr_failures').add({
        'platform': platform,
        'raw_text': rawText,
        'error_reason': errorReason ?? 'Unknown parsing failure',
        'parsed_data': parsedData,
        'timestamp': FieldValue.serverTimestamp(),
        'app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
      });

      _sessionSentHashes.add(textHash);
      await prefs.setInt(countKey, currentCount + 1);
      
      if (kDebugMode) {
        print('OCR Error Logged to Firestore for platform: $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log OCR error: $e');
      }
    }
  }
  Future<void> logCorrection({
    required String platform,
    required String rawText,
    required Map<String, dynamic> correctedData,
  }) async {
    try {
      final textHash = rawText.hashCode.toString();
      
      // 1. 이번 세션 중복 전송 방지
      if (_sessionSentHashes.contains('corr_$textHash')) {
        return;
      }

      // 2. 일일 전송 횟수 제한 (하루 최대 5회까지만 전송 - 비용 제로 완벽 방어)
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final countKey = 'ocr_corr_count_$todayStr';
      final currentCount = prefs.getInt(countKey) ?? 0;

      if (currentCount >= 5) {
        if (kDebugMode) print('OCR Correction Log skipped due to daily quota limit (5)');
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      
      await FirebaseFirestore.instance.collection('ocr_corrections').add({
        'platform': platform,
        'raw_text': rawText,
        'corrected_data': correctedData,
        'timestamp': FieldValue.serverTimestamp(),
        'app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
      });

      _sessionSentHashes.add('corr_$textHash');
      await prefs.setInt(countKey, currentCount + 1);
      
      if (kDebugMode) {
        print('OCR Correction Logged to Firestore for platform: $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log OCR correction: $e');
      }
    }
  }
}

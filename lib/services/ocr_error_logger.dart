import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      
      // 이번 세션에서 이미 전송한 동일한 텍스트면 무시 (스팸 방지)
      if (_sessionSentHashes.contains(textHash)) {
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
      
      if (kDebugMode) {
        print('OCR Error Logged to Firestore for platform: $platform');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log OCR error: $e');
      }
    }
  }
}

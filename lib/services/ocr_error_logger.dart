import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OcrErrorLoggerService {
  static final OcrErrorLoggerService instance = OcrErrorLoggerService._internal();

  OcrErrorLoggerService._internal();

  final Set<String> _sessionSentHashes = {};

  Future<bool> _canUploadSuccessToday(SharedPreferences prefs, String todayStr) async {
    final countKey = 'success_upload_count_$todayStr';
    final currentCount = prefs.getInt(countKey) ?? 0;
    return currentCount < 5;
  }

  Future<void> _incrementSuccessUploadCount(SharedPreferences prefs, String todayStr) async {
    final countKey = 'success_upload_count_$todayStr';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
  }

  Future<bool> _canUploadToday(SharedPreferences prefs, String todayStr) async {
    final countKey = 'unified_upload_count_$todayStr';
    final currentCount = prefs.getInt(countKey) ?? 0;
    return currentCount < 5;
  }

  Future<void> _incrementUploadCount(SharedPreferences prefs, String todayStr) async {
    final countKey = 'unified_upload_count_$todayStr';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
  }

  Future<void> logError({
    required String platform,
    required String rawText,
    String? errorReason,
    Map<String, dynamic>? parsedData,
  }) async {
    try {
      final textHash = rawText.hashCode.toString();
      
      if (_sessionSentHashes.contains(textHash)) return;

      if (Random().nextDouble() > 0.3) {
        if (kDebugMode) print('OCR Error Log skipped due to sampling');
        return;
      }

      // No daily limit for error logs
      // final prefs = await SharedPreferences.getInstance();
      // final todayStr = DateTime.now().toIso8601String().substring(0, 10);

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
      
      if (kDebugMode) print('OCR Error Logged to Firestore for platform: $platform');
    } catch (e) {
      if (kDebugMode) print('Failed to log OCR error: $e');
    }
  }

  Future<void> logCorrection({
    required String platform,
    required String rawText,
    required Map<String, dynamic> correctedData,
  }) async {
    try {
      final textHash = rawText.hashCode.toString();
      
      if (_sessionSentHashes.contains('corr_$textHash')) return;

      // No daily limit for correction logs

      final packageInfo = await PackageInfo.fromPlatform();
      
      await FirebaseFirestore.instance.collection('ocr_corrections').add({
        'platform': platform,
        'raw_text': rawText,
        'corrected_data': correctedData,
        'timestamp': FieldValue.serverTimestamp(),
        'app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
      });

      _sessionSentHashes.add('corr_$textHash');
      
      if (kDebugMode) print('OCR Correction Logged to Firestore for platform: $platform');
    } catch (e) {
      if (kDebugMode) print('Failed to log OCR correction: $e');
    }
  }

  Future<void> logSharedCallPoint({
    required Map<String, dynamic> rowData,
  }) async {
    try {
      // Create a unique hash for this data to prevent duplicate uploads in the same session
      final dataHash = "${rowData['start_location']}_${rowData['end_location']}_${rowData['gross_fare']}_${rowData['program']}".hashCode.toString();
      
      if (_sessionSentHashes.contains('shared_$dataHash')) return;

      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      
      if (!await _canUploadSuccessToday(prefs, todayStr)) {
        if (kDebugMode) print('Shared Call Point Log skipped due to success daily limit (5)');
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      
      await FirebaseFirestore.instance.collection('shared_call_points').add({
        'type': 'log',
        'program': rowData['program'] ?? '',
        'start_location': rowData['start_location'] ?? '',
        'start_lat': rowData['start_lat'],
        'start_lng': rowData['start_lng'],
        'end_location': rowData['end_location'] ?? '',
        'end_lat': rowData['end_lat'],
        'end_lng': rowData['end_lng'],
        'gross_fare': rowData['gross_fare'] ?? 0,
        'waypoint': rowData['waypoint'] ?? '',
        'drive_time': rowData['drive_time'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
      });

      _sessionSentHashes.add('shared_$dataHash');
      await _incrementSuccessUploadCount(prefs, todayStr);
      
      if (kDebugMode) print('Shared Call Point Logged to Firestore');
    } catch (e) {
      if (kDebugMode) print('Failed to log shared call point: $e');
    }
  }
}
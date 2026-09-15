import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firestore에서 OCR 파싱 룰 JSON을 가져오고 로컬에 캐싱하는 서비스
class FirestoreRuleService {
  FirestoreRuleService._();

  static const String _collectionPath = 'parsing_rules';
  static const String _versionDoc = 'version';
  static const String _rulesDoc = 'rules';

  static const String _prefVersionKey = 'ocr_rules_version';
  static const String _prefRulesKey = 'ocr_rules_json';

  static Map<String, dynamic>? _memoryCache;

  /// 앱 시작 시 호출: 로컬 캐시를 메모리에 올리고, 백그라운드에서 최신 버전 체크
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_prefRulesKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        _memoryCache = jsonDecode(cachedJson) as Map<String, dynamic>;
        if (kDebugMode) {
          print('[FirestoreRule] Loaded rules from local cache (version: ${prefs.getInt(_prefVersionKey)})');
        }
      }

      // 백그라운드에서 업데이트 체크 (UI 블로킹 없음)
      checkAndUpdate().catchError((e) {
        if (kDebugMode) print('[FirestoreRule] Background update failed: $e');
      });
    } catch (e) {
      if (kDebugMode) print('[FirestoreRule] Initialize failed: $e');
    }
  }

  /// Firestore 버전 확인 후 필요 시 룰 다운로드
  static Future<void> checkAndUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt(_prefVersionKey) ?? 0;

      final versionSnap = await FirebaseFirestore.instance
          .collection(_collectionPath)
          .doc(_versionDoc)
          .get();

      if (!versionSnap.exists) {
        if (kDebugMode) print('[FirestoreRule] Remote version doc not found.');
        return;
      }

      final remoteVersion = (versionSnap.data()?['version'] ?? 0) as int;

      if (remoteVersion > localVersion) {
        if (kDebugMode) {
          print('[FirestoreRule] New rules found! (Local: $localVersion, Remote: $remoteVersion)');
        }
        await _downloadAndCacheRules(remoteVersion, prefs);
      } else {
        if (kDebugMode) {
          print('[FirestoreRule] Rules are up to date (Version: $localVersion)');
        }
      }
    } catch (e) {
      if (kDebugMode) print('[FirestoreRule] checkAndUpdate error: $e');
      throw e;
    }
  }

  static Future<void> _downloadAndCacheRules(int newVersion, SharedPreferences prefs) async {
    final rulesSnap = await FirebaseFirestore.instance
        .collection(_collectionPath)
        .doc(_rulesDoc)
        .get();

    if (!rulesSnap.exists || rulesSnap.data() == null) {
      if (kDebugMode) print('[FirestoreRule] Rules doc is empty.');
      return;
    }

    final rulesData = rulesSnap.data()!;
    final jsonStr = jsonEncode(rulesData);

    await prefs.setString(_prefRulesKey, jsonStr);
    await prefs.setInt(_prefVersionKey, newVersion);

    _memoryCache = rulesData;
    if (kDebugMode) print('[FirestoreRule] Successfully updated to version $newVersion');
  }

  /// 파싱 엔진에서 즉시 룰을 가져갈 수 있도록 동기(sync) 반환
  static Map<String, dynamic>? get rules => _memoryCache;
}

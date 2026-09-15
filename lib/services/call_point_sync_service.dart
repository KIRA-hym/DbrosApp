import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'settings_service.dart';
import 'db_helper.dart';

class CallPointSyncService {
  static const String _jsonUrl = 'https://dbros-apps-7bbmw4.firebasestorage.app/o/shared_coordinates.json?alt=media';
  static const String _versionUrl = 'https://dbros-apps-7bbmw4.firebasestorage.app/o/shared_coordinates_metadata.json?alt=media';

  static Future<int> checkServerVersion() async {
    try {
      final response = await http.get(Uri.parse('$_versionUrl&_t=${DateTime.now().millisecondsSinceEpoch}'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['version'] ?? 0;
      }
    } catch (e) {
      debugPrint('버전 체크 실패: $e');
    }
    return 0;
  }

  static Future<bool> isUpdateAvailable() async {
    final serverVersion = await checkServerVersion();
    final localVersion = SettingsService.localCallPointVersion;
    return serverVersion > localVersion;
  }

  static Future<bool> downloadAndUpdateMapData(int targetVersion) async {
    try {
      final response = await http.get(Uri.parse('$_jsonUrl&_t=${DateTime.now().millisecondsSinceEpoch}'));
      if (response.statusCode == 200) {
        final List<dynamic> points = jsonDecode(response.body);
        final db = await DriveLogDatabase.instance.database;
        
        await db.transaction((txn) async {
          await txn.delete('call_points');
          final batch = txn.batch();
          for (var point in points) {
            batch.insert('call_points', {
              'start_lat': point['start_lat'],
              'start_lng': point['start_lng'],
              'type': point['type'] ?? 'other',
              'created_at': point['created_at'] ?? DateTime.now().toIso8601String(),
            });
          }
          await batch.commit(noResult: true);
        });

        await SettingsService.setLocalCallPointVersion(targetVersion);
        return true;
      }
    } catch (e) {
      debugPrint('맵 데이터 업데이트 실패: $e');
    }
    return false;
  }
}
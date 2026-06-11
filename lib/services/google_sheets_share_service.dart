import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dbros_app/services/db_helper.dart';

class GoogleSheetsShareService {
  // TODO: 대표님이 Apps Script 배포 후 발급받은 URL을 여기에 붙여넣으세요.
  static const String _scriptUrl = 'YOUR_GOOGLE_APPS_SCRIPT_WEB_APP_URL';

  static Future<bool> isConfigured() async {
    return _scriptUrl.startsWith('https://script.google.com/macros/s/');
  }

  /// 1. 내 좌표 공유 (POST)
  static Future<bool> shareMyCoordinates(String userUid) async {
    if (!await isConfigured()) return false;

    // drive_logs에서 위/경도가 존재하는 모든 내역 추출
    final db = await DriveLogDatabase.instance.database;
    final logs = await db.query(
      'drive_logs',
      where: 'start_lat IS NOT NULL AND start_lat != 0.0 AND start_lng IS NOT NULL AND start_lng != 0.0',
    );

    if (logs.isEmpty) return true; // 공유할 데이터 없음

    final List<Map<String, dynamic>> payload = logs.map((log) {
      return {
        'timestamp': log['created_at'] ?? DateTime.now().toIso8601String(),
        'user_id': userUid,
        'lat': log['start_lat'],
        'lng': log['start_lng'],
        'type': 'shared_log',
        'drive_time': log['drive_time'] ?? '',
        'program': log['program'] ?? '',
        'start_location': log['start_location'] ?? '',
        'waypoint': log['waypoint'] ?? '',
        'end_location': log['end_location'] ?? '',
        'gross_fare': log['gross_fare'] ?? 0,
        'memo': log['memo'] ?? '',
      };
    }).toList();

    try {
      final response = await http.post(
        Uri.parse(_scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Google Sheets Share Error: $e');
      return false;
    }
  }

  /// 2. 주변콜맵 업데이트 (GET)
  static Future<bool> fetchSharedCoordinates() async {
    if (!await isConfigured()) return false;

    try {
      final response = await http.get(Uri.parse(_scriptUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        final db = await DriveLogDatabase.instance.database;
        await db.transaction((txn) async {
          for (var item in data) {
            final double lat = double.tryParse(item['lat'].toString()) ?? 0.0;
            final double lng = double.tryParse(item['lng'].toString()) ?? 0.0;
            if (lat == 0.0 || lng == 0.0) continue;

            final String uid = item['user_id']?.toString() ?? '';
            final String createdAt = item['timestamp']?.toString() ?? '';
            final String rawType = item['type']?.toString() ?? 'shared';
            final String mappedType = rawType == 'reference' ? 'reference' : 'shared';
            
            // 중복 방지 로직: 같은 좌표와 시간의 데이터가 있는지 확인
            final existing = await txn.query(
              'call_points',
              where: 'type = ? AND start_lat = ? AND start_lng = ? AND created_at = ?',
              whereArgs: [mappedType, lat, lng, createdAt],
              limit: 1,
            );

            if (existing.isEmpty) {
              await txn.insert('call_points', {
                'type': mappedType,
                'is_mine': 0,
                'start_location': item['start_location']?.toString() ?? '',
                'start_lat': lat,
                'start_lng': lng,
                'end_location': item['end_location']?.toString() ?? '',
                'drive_time': item['drive_time']?.toString() ?? '',
                'program': item['program']?.toString() ?? '',
                'created_at': createdAt,
                'user_id': uid,
                'gross_fare': int.tryParse(item['gross_fare'].toString()) ?? 0,
                'waypoint': item['waypoint']?.toString() ?? '',
              });
            }
          }
        });
        
        DriveLogDatabase.instance.notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print('Google Sheets Fetch Error: $e');
      return false;
    }
  }
}

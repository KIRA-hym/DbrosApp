import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dbros_app/services/db_helper.dart';
import 'package:dbros_app/services/auth_service.dart';
import 'settings_service.dart';

class GoogleSheetsShareService {
  static String get _scriptUrl => SettingsService.gasWebhookUrl;

  static Future<bool> isConfigured() async {
    return _scriptUrl.startsWith('https://script.google.com/macros/s/');
  }

  /// 1. 내 좌표 공유 (POST)
  static Future<({bool success, String message})> shareMyCoordinates(String userUid) async {
    if (!await isConfigured()) return (success: false, message: 'URL이 설정되지 않았습니다.');

    // drive_logs에서 위/경도가 존재하는 모든 내역 추출
    final db = await DriveLogDatabase.instance.database;
    final logs = await db.query(
      'drive_logs',
      where: 'start_lat IS NOT NULL AND start_lat != 0.0 AND start_lng IS NOT NULL AND start_lng != 0.0',
    );

    if (logs.isEmpty) return (success: true, message: '공유할 좌표 데이터가 없습니다.');

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
        // 메모 및 요금은 개인정보/민감정보이므로 공유에서 제외
      };
    }).toList();

    try {
      final response = await http.post(
        Uri.parse(_scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200 || response.statusCode == 302) {
        try {
          final result = jsonDecode(response.body);
          if (result['status'] == 'success') {
            return (success: true, message: '성공');
          } else {
            return (success: false, message: '서버 에러: ${result['message'] ?? '알 수 없는 오류'}');
          }
        } catch (_) {
          return (success: false, message: '응답 해석 실패 (구글 시트 웹앱 설정을 확인하세요)');
        }
      }
      return (success: false, message: 'HTTP 상태 코드 오류: ${response.statusCode}');
    } catch (e) {
      print('Google Sheets Share Error: $e');
      if (e.toString().contains('Timeout')) {
        return (success: false, message: '시간 초과 (데이터가 많거나 네트워크가 불안정합니다)');
      }
      return (success: false, message: '오류 발생: $e');
    }
  }

  /// 2. 주변콜맵 업데이트 (GET)
  static Future<bool> fetchSharedCoordinates() async {
    if (!await isConfigured()) return false;

    try {
      final response = await http.get(Uri.parse(_scriptUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 || response.statusCode == 302) {
        final List<dynamic> data = jsonDecode(response.body);
        final String currentUserId = AuthService.instance.userDoc?['uid']?.toString() ?? 'unknown';
        
        final db = await DriveLogDatabase.instance.database;
        await db.transaction((txn) async {
          // 기존에 잘못 저장된 내 공유 좌표 (type='shared'이고 user_id가 내 uid) 일괄 삭제
          if (currentUserId != 'unknown' && currentUserId.isNotEmpty) {
            await txn.delete(
              'call_points',
              where: 'type = ? AND user_id = ?',
              whereArgs: ['shared', currentUserId],
            );
          }

          for (var item in data) {
            final double lat = double.tryParse(item['lat'].toString()) ?? 0.0;
            final double lng = double.tryParse(item['lng'].toString()) ?? 0.0;
            if (lat == 0.0 || lng == 0.0) continue;

            final String uid = item['user_id']?.toString() ?? '';
            // 내 좌표는 주변콜맵(공유 좌표)으로 다시 저장하지 않음 (겹침 방지)
            if (uid.isNotEmpty && uid == currentUserId) continue;

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
        
        return true;
      }
      return false;
    } catch (e) {
      print('Google Sheets Fetch Error: $e');
      return false;
    }
  }
}

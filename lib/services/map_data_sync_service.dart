import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';

class MapDataSyncService {
  // 테스트용 깃허브 Raw 링크 (나중에 관리자웹에서 생성한 Firebase Storage 링크로 변경)
  static const String defaultSyncUrl = 
      'https://firebasestorage.googleapis.com/v0/b/dbros-apps-7bbmw4.firebasestorage.app/o/map_data%2Fcommon_points.json?alt=media';

  static Future<void> syncCommonPoints({String url = defaultSyncUrl}) async {
    if (kIsWeb) return; // 웹 환경은 SQLite(sqflite) 미지원

    try {
      debugPrint('[MapDataSync] JSON 다운로드 시작: $url');
      String jsonString = '';
      
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          jsonString = utf8.decode(response.bodyBytes);
        } else {
          debugPrint('[MapDataSync] 다운로드 실패 (${response.statusCode}). 로컬 에셋으로 폴백합니다.');
        }
      } catch (e) {
        debugPrint('[MapDataSync] 다운로드 예외 발생 ($e). 로컬 에셋으로 폴백합니다.');
      }

      if (jsonString.isEmpty) {
        // 폴백: assets/data/common_points.json 읽기
        jsonString = await rootBundle.loadString('assets/data/common_points.json');
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);

      if (jsonList.isEmpty) {
        debugPrint('[MapDataSync] JSON 데이터가 비어 있습니다.');
        return;
      }

      final db = await DriveLogDatabase.instance.database;

      await db.transaction((txn) async {
        // 1. 기존의 공통 마커(대기, 화장실, 셔틀, 남의 공유마커) 모두 삭제
        // 단, 내 기록(type='log' AND is_mine=1)은 절대 삭제되지 않도록 보호
        final deletedRows = await txn.delete(
          'call_points',
          where: "type != 'log'",
        );
        debugPrint('[MapDataSync] 기존 공통 마커 $deletedRows개 삭제됨');

        // 2. 새 JSON 데이터를 로컬 DB에 일괄 삽입
        final batch = txn.batch();
        for (final item in jsonList) {
          if (item is! Map<String, dynamic>) continue;
          
          batch.insert('call_points', {
            'type': item['type'] ?? 'reference',
            'is_mine': 0, // 외부에서 받은 데이터는 모두 내 것이 아님
            'start_location': item['start_location'],
            'start_lat': item['start_lat'],
            'start_lng': item['start_lng'],
            'end_location': item['end_location'],
            'drive_time': item['drive_time'],
            'program': item['program'],
            'created_at': item['created_at'] ?? DateTime.now().toIso8601String(),
            'user_id': item['user_id'] ?? 'admin',
            'gross_fare': item['gross_fare'] ?? 0,
            'waypoint': item['waypoint'],
            'memo': item['memo'],
          });
        }
        
        await batch.commit(noResult: true);
      });

      debugPrint('[MapDataSync] 공통 마커 ${jsonList.length}개 동기화 완료!');
    } catch (e) {
      debugPrint('[MapDataSync] 동기화 중 오류 발생: $e');
    }
  }
}

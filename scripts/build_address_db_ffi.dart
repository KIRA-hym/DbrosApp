import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

const chosungList = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];

String getChosung(String text) {
  final sb = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    final code = char.codeUnitAt(0);
    if (code >= 44032 && code <= 55203) {
      final index = ((code - 44032) / 588).floor();
      sb.write(chosungList[index]);
    } else if (char == ' ') {
      sb.write(' ');
    } else {
      sb.write(char);
    }
  }
  return sb.toString();
}

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;

  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync();
  }

  final dbPath = join(Directory.current.path, 'assets', 'address.db');
  final file = File(dbPath);
  if (file.existsSync()) {
    file.deleteSync();
  }

  var db = await databaseFactory.openDatabase(dbPath);
  await db.execute('''
    CREATE TABLE addresses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      full_name TEXT NOT NULL,
      cho_seong TEXT NOT NULL
    )
  ''');

  int totalCount = 0;

  // 1. 공공 API에서 지번(법정동) 주소 추출
  print('============================================');
  print('1. 지번주소(법정동) 2만건 API 추출 시작...');
  final sidoRes = await http.get(Uri.parse('https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=*00000000'));
  final sidoData = jsonDecode(utf8.decode(sidoRes.bodyBytes));
  
  for (var sido in sidoData['regcodes']) {
    final prefix = sido['code'].substring(0, 2);
    final sidoName = sido['name'];
    final url = 'https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=' + prefix + '*&is_ignore_zero=true';
    try {
      final detailRes = await http.get(Uri.parse(url));
      final detailData = jsonDecode(utf8.decode(detailRes.bodyBytes));
      if (detailData['regcodes'] != null) {
        var batch = db.batch();
        for (var item in detailData['regcodes']) {
          final name = item['name'] as String;
          batch.insert('addresses', {
            'full_name': name,
            'cho_seong': getChosung(name)
          });
          totalCount++;
        }
        await batch.commit();
      }
    } catch (e) {
      print(sidoName + ' 지번주소 에러: ' + e.toString());
    }
  }
  print('지번주소 완료. 현재 총 ' + totalCount.toString() + '건');
  print('============================================');

  // 2. 텍스트 파일에서 도로명 주소 추출
  print('2. 도로명주소 16만건 텍스트 파일 추출 시작...');
  final roadNamesFile = File(r'C:\Users\HYM\Downloads\202607_도로명_전체분\TN_SPRD_RDNM.txt');
  if (!roadNamesFile.existsSync()) {
    print('🚨 [경고] 도로명 텍스트 파일이 존재하지 않습니다!');
    print('도로명주소 파일이 없으므로 지번주소만 저장하고 종료합니다.');
  } else {
    try {
      final lines = await roadNamesFile.readAsLines();
      var batch = db.batch();
      int batchCount = 0;
      int roadCount = 0;
      
      // 중복 방지를 위한 Set (같은 시구 + 도로명이 여러번 나올 수 있음)
      final Set<String> uniqueRoads = {};

      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        
        final cols = line.split('|');
        if (cols.length > 7) {
          final roadName = cols[3].trim(); // 도로명
          final sido = cols[5].trim();     // 시도명
          final sigungu = cols[6].trim();  // 시군구명
          
          if (roadName.isEmpty || sido.isEmpty) continue;
          
          final fullRoadName = sigungu.isEmpty 
              ? sido + ' ' + roadName 
              : sido + ' ' + sigungu + ' ' + roadName;
              
          if (!uniqueRoads.contains(fullRoadName)) {
            uniqueRoads.add(fullRoadName);
            batch.insert('addresses', {
              'full_name': fullRoadName,
              'cho_seong': getChosung(fullRoadName)
            });
            batchCount++;
            roadCount++;
            totalCount++;
            
            if (batchCount >= 1000) {
              await batch.commit();
              batch = db.batch();
              batchCount = 0;
            }
          }
        }
      }
      if (batchCount > 0) {
        await batch.commit();
      }
      print('도로명주소 고유 ' + roadCount.toString() + '건 추출 완료!');
    } catch (e) {
      print('도로명주소 처리 중 에러 발생: ' + e.toString());
    }
  }

  print('============================================');
  print('3. 인덱스 생성 중...');
  await db.execute('CREATE INDEX idx_cho_seong ON addresses (cho_seong)');
  await db.execute('CREATE INDEX idx_full_name ON addresses (full_name)');

  final res = await db.rawQuery('SELECT count(*) as cnt FROM addresses');
  final savedCount = res.first['cnt'];
  
  await db.close();
  print('✅ 하이브리드 통합 address.db 생성 완료! 총 ' + totalCount.toString() + '개의 주소를 파싱했고, 실제 DB에는 ' + savedCount.toString() + '개가 저장되었습니다.');
}

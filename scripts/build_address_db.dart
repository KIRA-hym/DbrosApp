import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

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
  final assetsDir = Directory('../assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync();
  }
  
  final sqlFile = File('address_insert.sql');
  final sink = sqlFile.openWrite();
  
  sink.writeln('DROP TABLE IF EXISTS addresses;');
  sink.writeln('CREATE TABLE addresses (id INTEGER PRIMARY KEY AUTOINCREMENT, full_name TEXT NOT NULL, cho_seong TEXT NOT NULL);');
  sink.writeln('BEGIN TRANSACTION;');

  print('전국 법정동 데이터를 가져오는 중...');
  
  try {
    final res = await http.get(Uri.parse('https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=*00000000'));
    final sidoData = jsonDecode(res.body);
    
    int totalCount = 0;
    for (var sido in sidoData['regcodes'] ?? []) {
      final prefix = (sido['code'] as String).substring(0, 2);
      final sidoName = sido['name'];
      
      final detailRes = await http.get(Uri.parse('https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=\${prefix}*&is_ignore_zero=true'));
      final detailData = jsonDecode(detailRes.body);
      
      for (var item in detailData['regcodes'] ?? []) {
        final name = item['name'] as String;
        final chosung = getChosung(name);
        final safeName = name.replaceAll("'", "''");
        final safeChosung = chosung.replaceAll("'", "''");
        sink.writeln("INSERT INTO addresses (full_name, cho_seong) VALUES ('\$safeName', '\$safeChosung');");
        totalCount++;
      }
      print('\$sidoName 완료... (현재 총 \$totalCount건)');
    }
    
    sink.writeln('CREATE INDEX idx_cho_seong ON addresses (cho_seong);');
    sink.writeln('CREATE INDEX idx_full_name ON addresses (full_name);');
    sink.writeln('COMMIT;');
    await sink.close();
    print('SQL 스크립트 생성 완료. sqlite3 커맨드로 DB를 빌드하세요.');
    
  } catch (e) {
    print('오류 발생: \$e');
  }
}

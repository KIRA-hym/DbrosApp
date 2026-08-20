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
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync();
  }

  final csvFile = File('assets/address.csv');
  final sink = csvFile.openWrite();
  sink.writeln('full_name,cho_seong');

  print('전국 법정동 데이터를 가져오는 중...');

  // 시도 코드 가져오기
  final sidoRes = await http.get(Uri.parse('https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=*00000000'));
  final sidoData = jsonDecode(utf8.decode(sidoRes.bodyBytes));
  
  int totalCount = 0;

  for (var sido in sidoData['regcodes']) {
    final prefix = sido['code'].substring(0, 2);
    final sidoName = sido['name'];

    // 각 시도별로 전체 하위 코드 가져오기 (읍면동)
    final url = 'https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes?regcode_pattern=\$prefix*&is_ignore_zero=true';
    try {
      final detailRes = await http.get(Uri.parse(url));
      final detailData = jsonDecode(utf8.decode(detailRes.bodyBytes));
      
      int sidoCount = 0;
      if (detailData['regcodes'] != null) {
        for (var item in detailData['regcodes']) {
          final name = item['name'] as String;
          final choSeong = getChosung(name);
          // CSV 작성
          sink.writeln('\$name,\$choSeong');
          sidoCount++;
        }
      }
      totalCount += sidoCount;
      print('\$sidoName 완료... (현재 총 \$totalCount건)');
    } catch (e) {
      print('\$sidoName 데이터를 가져오는 중 에러 발생: \$e');
    }
  }

  await sink.flush();
  await sink.close();
  
  print('✅ 리얼 데이터 기반 address.csv 생성 완료! 총 \$totalCount개의 주소가 저장되었습니다.');
  print('이 파일을 assets 폴더에 포함하고, 앱 실행 시 최초 1회 Sqflite DB로 밀어넣으면 됩니다.');
}

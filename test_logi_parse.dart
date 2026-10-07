import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/logi_fare_parse.dart';

void main() {
  print('TEST 155000 CODEUNITS: ' + '155000'.codeUnits.toString() + ' TEST: \${parseLogiFareFromOcrText('155000')}');

  final logText = '''SKT 3:25 T
상세완료정보
발주사
이용개시변호
요금
입금액
고객
메모
적요
전화
전화2
출발지
도착지
경로
안내
&하나로(주)HnH 하나로
92201505137
155000
31000
법인
법인명:**차호우게리(전무님)
▶법인후불▶킥보드불가 정장필▶경유,
대기발생시종료후보고필
[하나로(주)HnH 02-3706-1004
10:29] 권정현기사님접수운행
고객과의 거리: 106748미터
000-0000-1686
편도/6
화11:30/세종금남면
SPC삼립세종공장>세종바우정원>
상세:세종 세종시 금남면 봉암리 시
151-0 SPC삼립 세종공장
아이파크1단지
출발지 특이사항입
서명
경기 성남시 정자동)1:26대기-분당정자동
지도
력
0
갱신
전화
전화
닫기''';

  for(final line in logText.split(RegExp(r'[\r\n]+'))) { print('LINE: ' + line + ' RUNES: ' + line.runes.toList().toString()); }    print('4: ' + RegExp(r'\d{9,}').hasMatch('155000').toString()); print('--- LOGI OCR PARSE ---');
  final result = LogiColmannerOcr.parseLogiColmanner(logText, isLogi: true);
  print('Start: \${result.startAddress}');
  print('Waypoint: \${result.waypoint}');
  print('End: \${result.endAddress}');
  print('Fare: \${result.grossFare}');
}

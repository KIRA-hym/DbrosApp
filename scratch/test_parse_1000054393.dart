import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  const rawText = """
O1:28
위치 : 합정동/ 합정역 잔액 : 119,644원
고객전화
지사명 올타대리(글로벌대리)
고객명 **
출발지
도착지
출도
서울 마포구 합정동
합정동삼아빌딩
차감합계
적요 /
상황실
서울 강서구 화곡동
화곡화이트마사지
경로거리 : 7.4km
요금 25,000원 (예상 수익금:19,162원)
현금 25000원
연락처
(예상소요시간 : 13분)
입금합계 합계 : 0원
합계 : 6,097원
상황실
예상 운행수수료 : 5,000원
예상 고용보험료 : 110원
예상 산자보험료 : 128원
025606200
접수시간 오전이1:2
고객위치
90 출도경로
운행 시작
||
킬안내
""";

  final parsed = LogiColmannerOcr.parseColmanner(rawText);
  print('--- PARSING RESULT ---');
  print('출발지: ${parsed.startLocation}');
  print('도착지: ${parsed.endLocation}');
  print('경유지: ${parsed.waypoint}');
  print('요금:   ${parsed.grossFare}');
}

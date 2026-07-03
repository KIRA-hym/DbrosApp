import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('OCR Parse Test', () {
    final logText = '''
14:57 6월 29일
17분 54초 남음
운행시작연기
운행 시작
요금
서명
850002
입금액
17000
법인
법인명:**** 박근영(대표님)
고객
퀵보드운행불가▶법인후불정장필
메모
[S하나로(주)HnH 02-3706-1004
14:54] 전화2만:담당팀장님
적요
고객과의 거리: 18055미터
전화
전화
02-3706-1004
전화2
전화
19:30/인천강화도 선창집장어구이 5/5
상세인천 강화군 선원면 신정리 319-10
선창집
출발지
도착지
서울 구로구 신도림동)신도림동 디큐브시티
고객D
4046
오더번호
1340496914
출발지
완료
배차
경로
안내
닫기
갱신
취소
처리
지도
<
''';

    final parsed = LogiColmannerOcr.parseLogi(logText);
    print('=================');
    print('요금: ${parsed.grossFare}');
    print('출발지: ${parsed.startLocation}');
    print('도착지: ${parsed.endLocation}');
    print('=================');
  });
}

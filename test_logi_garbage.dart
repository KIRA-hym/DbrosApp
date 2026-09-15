import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';

void main() {
  test('Logi Garbage Test', () {
    final text = '''
O1:17 iT
상세배차정보
운행 시작
발주사
이용개시번호
요금
입금액
고객
메모
적요
전화
전화2
출발지
도착지
고객D
오더번호
차량번호
경로
안내
TALK,
도로금0000/(F브디디
9260341111
25000
5000
17분 41초 남음
일반 스마트콜고객
[#삼삼오오콜(3355) 1688-3773 01:14]
고객과의 거리: 48n미터
0508-5098-9641
백석동 정릉갈비
상세:경가 고양시 일산동구 백석동 1163번지
서울 강서구 마곡동)서울 등촌동 파리바게뜨 양천향교점
421
지도
1346333396
출발지
완료
처리
배차
취소
갱신
5Ol5
운행시작연기
서명
전화
전화
닫기
''';

    final result = LogiColmannerOcr.parseLogi(text);
    print('총요금: ' + result.grossFare.toString() + '원');
    print('출발지: ' + result.startLocation);
    print('도착지: ' + result.endLocation);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'package:dbros_app/utils/tmap_trip_detail_ocr.dart';

void main() {
  group('Historical OCR Log Verification', () {

    // ─── [사례 1] 콜마너: 중산동→광주 태전동 ───────────────────────────────
    test('[콜마너] 중산동1988 → 광주태전동고불로 70,000원', () {
      const raw = '''
00:50 TT
위치 : 영종동/ 한라@ 잔액 : 293,806원
고객전화
출발지
카/인천중산동 1988
출도
적요
도착지 180-27(태전동 502-48)
인천 중구 중산동
입금합계
차감합계
경기 광주시 태전동 고불로
연락처
광주태전동고불로180-27
경로거리 : 75.2km
현금 0원
(예상소요시간 : 51분)
요금 10,000원 (예상 수의금:55,336원)
상황실
후불7OK]완료20분후입금> [앱접수]자동
합계 : 70,000원
예상 후불요금 : 70,000원
''';
      final p = LogiColmannerOcr.parseColmanner(raw);
      print('[콜마너 사례1]');
      print('  START: ${p.startLocation}');
      print('  END:   ${p.endLocation}');
      print('  FARE:  ${p.grossFare}');
      print('  WANT_START: 인천 중구 중산동 1988');
      print('  WANT_END:   경기 광주시 태전동 고불로 (180-27)');
      print('  WANT_FARE:  70000');
    });

    // ─── [사례 2] 로지: 가락동 성원상떼빌→영종자이아파트 60,000원 ─────────
    test('[로지] 가락동성원상떼빌 → 영종자이아파트 60,000원', () {
      const raw = '''
23:1
운행 시작
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
경로
안내
600002
16분 41초 남음
12000!
일반 일반/카드
카드후불!(원천징수)최종목적지
확인하시고 안전하고 친절히
운행해주세요.감사합니다^^*
(기본요금:0원, 1Km 1000원)[마중물대리
0508-5061-538
07089897449 23:07] (후불60,000/
종료10분후자동충전)카드후불!
가락동/성원상떼빌 1/2
(원천징수)최종목적지 확인하시고 안전하고
친절히 운행해주세요.감사합니다^^*
고객과의 거리: 324미터
상세:서울 송파구 가락동 80-0
송파성원상떼빌
출발지
지도
운행시작연기
인천 중구 운남동)영종자이아파트
완료
9 sil 86
처리
배차
취소
서명
갱신
전화
전화
닫기
''';
      final p = LogiColmannerOcr.parseLogi(raw);
      print('[로지 사례2]');
      print('  START: ${p.startLocation}');
      print('  END:   ${p.endLocation}');
      print('  FARE:  ${p.grossFare}');
      print('  WANT_START: 서울 송파구 가락동 80-0 송파성원상떼빌');
      print('  WANT_END:   인천 중구 운남동 영종자이아파트');
      print('  WANT_FARE:  60000');
    });

    // ─── [사례 3] 카카오: 외발산동 수협→위례송파로 36,800원 ────────────────
    test('[카카오] 외발산동수협강서수산시장 → 위례송파로 36,800원', () {
      const raw = '''
배정 완료
카드 | 확정
TALK
외발산동
수협 강서수산시장
서울 송파구 위례송파로 80
고객과 통화
고객과 만날 장소 길찾기
배정취소
36,800
밀어서 고객에게 도착알림
메뉴
100점
''';
      final p = KakaoCallCardOcr.parseScreen(const [], raw);
      print('[카카오 사례3]');
      print('  START: ${p.startLocation}');
      print('  END:   ${p.endLocation}');
      print('  FARE:  ${p.grossFare}');
      print('  WANT_START: 외발산동 수협 강서수산시장');
      print('  WANT_END:   서울 송파구 위례송파로 80');
      print('  WANT_FARE:  36800');
    });

    // ─── [사례 4] 카카오: 신사동 아디다스→군포 고산로 31,400원 ─────────────
    test('[카카오] 신사동아디다스가로수길 → 군포시고산로 31,400원', () {
      const raw = '''
00:53 T
배정 완료
카드 | 확정
TALK
신사동
아디다스오리지널스 가로수길점
경기 군포시 고산로 36
고객과 통화
고객과 만날 장소 길찾기
배정취소
고객에게 위치정보가 공유됩니다.
31,400
고객과 메시지
밀어서 고객에게 도착알림
메뉴
100점
''';
      final p = KakaoCallCardOcr.parseScreen(const [], raw);
      print('[카카오 사례4]');
      print('  START: ${p.startLocation}');
      print('  END:   ${p.endLocation}');
      print('  FARE:  ${p.grossFare}');
      print('  WANT_START: 신사동 아디다스오리지널스 가로수길점');
      print('  WANT_END:   경기 군포시 고산로 36');
      print('  WANT_FARE:  31400');
    });

    // ─── [사례 5] 로지: 수지상현동 스크린골프→금호동 두산A 50,000원 ─────────
    test('[로지] 수지상현동스크린골프존 → 금호동금호두산A104동 50,000원', () {
      const raw = '''
23:31 iT
운행 시작
요금
입금액
고객
메모
적요
전화
전화2
출발지
도착지
1기TD
경로
안내
50000
18분 24초 남음
10000
법인
법인명:*** 열티바이김재영대표
[고고 02-787-9999 23:24]
업체지원10,000/후불40,000/
의일오전충전
고객과의 거리: 555미터
02-1819-999
수지상현동[상현스크린골프존]
기사메모확인필 !오더잡으면상황실바로
통화편도콜도착10분후부터대기료지급(1분
당300원)고고콜자사기사에게1분먼저보임.
서울 성동구
출발지
상세:경기 용인시 수지구 상현동 101-4
상현스크린골프존
금호동3가)금호동금호두산AI04동
지도
운행시작연기
완료
처리
배차
5우90이
취소
갱신
서명
전화
전화
닫기
''';
      final p = LogiColmannerOcr.parseLogi(raw);
      print('[로지 사례5]');
      print('  START: ${p.startLocation}');
      print('  END:   ${p.endLocation}');
      print('  FARE:  ${p.grossFare}');
      print('  WANT_START: 경기 용인시 수지구 상현동 101-4 상현스크린골프존');
      print('  WANT_END:   서울 성동구 금호동3가 금호두산A104동');
      print('  WANT_FARE:  50000');
    });

    // ─── [사례 6] 티맵: 정발산동 연주음악학원→금정동 목화아파트 30,400원 ──
    test('[티맵] 정발산동연주음악학원 → 금정동목화아파트 30,400원', () {
      const raw = '''
23:58 % T T•
고객센터
연주음악학원
운행중
고양시 일산동구 정발산동 693-9
군포시 금정동 850
목화아파트
T 티맵으로 길안내
96%의 티맵 고객이 선호!
실수익 30,400P
운행완료
뛰ll0
A 사고신고
''';
      final p = TmapTripDetailOcr.tryParse(raw);
      print('[티맵 사례6]');
      print('  START: ${p?.startAddress}');
      print('  END:   ${p?.endAddress}');
      print('  FARE:  ${p?.grossFare}');
      print('  WANT_START: 고양시 일산동구 정발산동 693-9 연주음악학원');
      print('  WANT_END:   군포시 금정동 850 목화아파트');
      print('  WANT_FARE:  30400');
    });

    // ─── [사례 7] 오늘 작업한 로지 법인콜: 후불45,000+업체지원10,000 ──────
    test('[로지] 법인콜 후불45,000+업체지원10,000=55,000원 (오늘 작업)', () {
      const raw = '''
상세배차정보
운행 시작
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
55000
16분 44초 남음
11000
법인
법인명:*** 에셋플러은성민전무
[고고 02-787-9999 19:08]
후불45,000/업체수동입금/
*차비흡연기사님요청 **회사출발시지하2층지
정주차자리(0129표시)**
업체지원10,000 )
고객과의 거리: 981미터
0508-5019-1181
등촌동+[SBA국제유통센터]
기사메모확인필!오더잡으면상황실바로
통화편도콜도착10
''';
      final p = LogiColmannerOcr.parseLogi(raw);
      print('[로지 사례7 - 오늘 작업]');
      print('  FARE:  ${p.grossFare}');
      print('  WANT_FARE:  55000');
      expect(p.grossFare, 55000);
    });

    // ─── [사례 8] 오늘 작업한 콜마너 기형 주소: 장항→안양관악역 ─────────
    test('[콜마너] 기형 레이아웃 장항제2공영주차장→안양관악역 (오늘 작업)', () {
      const raw = '''
21:0 T
액: 242,049원
고객전화
도착지
출도
출발지 장항제2공영주차장입구 천사
적요
입금합계
고객정보
경기 고양시일산동구 장항동
경기 안양시만안구 석수동 안양관악역 3-1
주차까지 마무리1 예상 후불요금 : 50,000원
경로거리 :37.8km
''';
      final p = LogiColmannerOcr.parseColmanner(raw);
      print('[콜마너 사례8 - 오늘 작업]');
      print('  START: ${p.startLocation}');
      print('  END:   ${p.endLocation}');
      print('  WANT_START: 경기 고양시일산동구 장항동 장항제2공영주차장입구');
      print('  WANT_END:   경기 안양시만안구 석수동 안양관악역');
      expect(p.startLocation, contains('고양시'));
      expect(p.startLocation, contains('장항제2공영주차장입구'));
      expect(p.endLocation, contains('안양시'));
    });
  });
}

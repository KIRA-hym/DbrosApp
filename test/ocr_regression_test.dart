import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'package:dbros_app/utils/kakao_custom_call_ocr.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/logi_fare_parse.dart';
import 'package:dbros_app/utils/tmap_trip_detail_ocr.dart';

void main() {
  group('Kakao custom OCR regression', () {
    test('extracts labeled start/end and payment split', () {
      const rawText = '''
맞춤콜 프로 단독배정
출발 도보 759m(약11분)
도착 약 44분 운행
출발 상봉동 디즈니골프 상봉역점
도착 🤍 경기 성남시 분당구 분당로 17
약 44분 운행
실제 수익 카드 | 확정 | 36,000 P
추천가 콜밭도착 10점
거절 2 초 뒤 자동수락
''';

      final parsed = KakaoCustomCallOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '상봉동 디즈니골프 상봉역점');
      expect(parsed.endLocation, '경기 성남시 분당구 분당로 17');
      expect(parsed.grossFare, 36000);
      expect(parsed.paymentMethod, '카드');
    });

    test('extracts destination with emoji and card fare', () {
      const rawText = '''
맞춤콜 프로 단독배정
출발 도보 2.6km(약44분)
도착 약 15분 운행
출발 정자동 푸른청과
도착 🤍 경기 용인 수지구 동천동 경기도 용인시 수지구 고기로 89
약 15분 운행
실제 수익 카드 | 확정 | 23,200 P
추천가 10점
거절 1 초 뒤 자동수락
''';

      final parsed = KakaoCustomCallOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '정자동 푸른청과');
      expect(parsed.endLocation, '경기 용인 수지구 동천동 경기도 용인시 수지구 고기로 89');
      expect(parsed.grossFare, 23200);
      expect(parsed.paymentMethod, '카드');
    });

    test('multiline labeled departure and destination', () {
      const rawText = '''
맞춤콜 프로 단독배정
출발 도보 759m(약11분)
도착 약 44분 운행
출발 상봉동 디즈니골프
상봉역점 2층
도착 🤍 경기 성남시 분당구 분당로 17
분당타워 1201호
약 44분 운행
실제 수익 카드 | 확정 | 36,000 P
''';
      final parsed = KakaoCustomCallOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '상봉동 디즈니골프 상봉역점 2층');
      expect(parsed.endLocation, '경기 성남시 분당구 분당로 17 분당타워 1201호');
      expect(parsed.grossFare, 36000);
    });
  });

  group('Kakao card OCR regression', () {
    test('general type1 with waypoint and card fare', () {
      const rawText = '''
배정 완료
배정취소 메뉴
중동
이치화로 용인동백점
죽전동 경유
경기 성남 분당구 수내동
파크타운대림아파트
100점
카드 | 확정
29,600 P
고객과 통화
고객과 메시지
고객과 만날 장소 길찾기
고객에게 위치정보가 공유됩니다.
밀어서 고객에게 도착알림
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '중동 이치화로 용인동백점');
      expect(parsed.endLocation, '경기 성남 분당구 수내동 파크타운대림아파트');
      expect(parsed.waypoint, '죽전동 경유');
      expect(parsed.grossFare, 29600);
    });

    test('general type1 uses top datetime for drive time not departure', () {
      const rawText = '''
19:32 5월 11일
배정 완료
배정취소 메뉴
중동
이치화로 용인동백점
죽전동 경유
경기 성남 분당구 수내동
파크타운대림아파트
100점
카드 | 확정
29,600 P
고객과 통화
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.driveTimeHm, '19:32');
      expect(parsed.startLocation, '중동 이치화로 용인동백점');
      expect(parsed.endLocation, '경기 성남 분당구 수내동 파크타운대림아파트');
    });

    test('general type1 ignores dotted OCR clock before addresses', () {
      const rawText = '''
19.32 5월 11일
배정 완료
배정취소 메뉴
중동
이치화로 용인동백점
경기 성남 분당구 수내동
파크타운대림아파트
카드 | 확정
29,600 P
고객과 통화
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.driveTimeHm, '19:32');
      expect(parsed.startLocation, '중동 이치화로 용인동백점');
      expect(parsed.endLocation, '경기 성남 분당구 수내동 파크타운대림아파트');
    });

    test('general type1 drops D1 parking label and merges two-line departure', () {
      const rawText = '''
22:49 ㅠ
배정 완료
카드 | 확정
D1
여의도동
신한은행 서여의도금융센터
서울 강동구 성내동
고객과 통화
강동구청
고객과 만날 장소 길찾기
배정취소
29,600
고객과 메시지
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '여의도동 신한은행 서여의도금융센터');
      expect(parsed.endLocation, '서울 강동구 성내동 강동구청');
      expect(parsed.grossFare, 29600);
    });

    test('general type1 strips OCR-split 위치정보 footer from destination', () {
      const rawText = '''
1:19 % TT
배정 완료
카드 | 확정
문래동3가
스트롱무브
서울 양천구 신월동
강서성결행복한홈스쿨 지역아동센터
고객과 통화
고객과 만날 장소 길찾기
배정취소
고객에게 위치정 보가 공유됩니다
11,600
고객과 메시지
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '문래동3가 스트롱무브');
      expect(parsed.endLocation, '서울 양천구 신월동 강서성결행복한홈스쿨 지역아동센터');
      expect(parsed.grossFare, 11600);
    });

    test('pro type2 with red banner and card fare', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
배정취소 가능 잔여 시간 : 12초
동작구 노량진동 노량진수산시장
부천시원미구 상동 꿈동산신안아파트
법인 무료보험 200점
카드 | 확정
24,000 P
고객 상황실 메모
고객과 만날 장소 길찾기
출발지에 도착하시면 도착완료 해주세요.
밀어서 고객에게 도착알림
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '동작구 노량진동 노량진수산시장');
      expect(parsed.endLocation, '부천시원미구 상동 꿈동산신안아파트');
      expect(parsed.grossFare, 24000);
    });

    test('general type2 cash fare with subsidy', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
배정취소 가능 잔여 시간 : 15초
미추홀구 학익동 일동수산회직판장
연수구 송도동 송도글로벌파크베르디움아파트
무료보험 100점
현금 | 확정
25,000원
수익 20,000 P + 지원금 3,000P
고객 상황실 메모
고객과 만날 장소 길찾기
출발지에 도착하시면 도착완료 해주세요.
밀어서 고객에게 도착알림
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '미추홀구 학익동 일동수산회직판장');
      expect(parsed.endLocation, '연수구 송도동 송도글로벌파크베르디움아파트');
      expect(parsed.grossFare, 23000);
    });

    test('general type2 destination stops before cash confirmation', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
미추홀구 학익동 일동수산회직판장
연수구 송도동 송도글로벌파크베르디움아파트
25,000원
무료보험
100점
현금
| 확정
수익 20,000 P + 지원금 3,000P
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.endLocation, '연수구 송도동 송도글로벌파크베르디움아파트');
      expect(parsed.grossFare, 23000);
    });

    test('general type2 strips fare suffix merged into destination line', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
미추홀구 학익동 일동수산회직판장
연수구 송도동 송도글로벌파크베르디움아파트 25,000원
현금 | 확정
25,000원
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.endLocation, '연수구 송도동 송도글로벌파크베르디움아파트');
    });

    test('general type2 ignores datetime meta before addresses', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
19:32 5월 11일
경기 김포시 구래동 김포한강신도시
서울 강서구 방화동 서울 방화동
무료보험 100점
카드 | 확정
16,800 P
고객 상황실 메모
고객과 만날 장소 길찾기
출발지에 도착하시면 도착완료 해주세요.
밀어서 고객에게 도착알림
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '경기 김포시 구래동 김포한강신도시');
      expect(parsed.endLocation, '서울 강서구 방화동 서울 방화동');
      expect(parsed.grossFare, 16800);
    });

    test('general type2 keeps POI-only departure line', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
하성 국수랑막창이랑
김포시 장기동 장기동 19
무료보험 100점
카드 | 확정
20,000 P
고객 상황실 메모
고객과 만날 장소 길찾기
출발지에 도착하시면 도착완료 해주세요.
밀어서 고객에게 도착알림
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '하성 국수랑막창이랑');
      expect(parsed.endLocation, '김포시 장기동 장기동 19');
      expect(parsed.grossFare, 20000);
    });

    test('detects general type2 when situation room OCR is split', () {
      const rawText = '''
T 전화 배정 완료
배정취소
메뉴
배정취소 가능 잔여 시간 : 15초
미추홀구 학익동 일동수산회직판장
연수구 송도동 송도글로벌파크베르디움아파트
무료보험
100점
현금 | 확정
25,000원
고객
상황실
메모
고객과 만날 장소 길찾기
''';
      expect(
        KakaoCallCardOcr.detectKakaoProgram(rawText),
        KakaoCallCardOcr.programGeneral,
      );
    });

    test('detects general type2 without situation room when assignment header remains', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
배정취소 가능 잔여 시간 : 12초
경기 김포시 구래동 김포한강신도시
서울 강서구 방화동 서울 방화동
무료보험 100점
카드 | 확정
16,800 P
고객과 만날 장소 길찾기
출발지에 도착하시면 도착완료 해주세요.
''';
      expect(
        KakaoCallCardOcr.detectKakaoProgram(rawText),
        KakaoCallCardOcr.programGeneral,
      );
    });

    test('detects pro type2 with corporate insurance', () {
      const rawText = '''
T 전화 배정 완료
배정취소 메뉴
동작구 노량진동 노량진수산시장
부천시원미구 상동 꿈동산신안아파트
법인 무료보험 200점
카드 | 확정
24,000 P
고객 상황실 메모
''';
      expect(
        KakaoCallCardOcr.detectKakaoProgram(rawText),
        KakaoCallCardOcr.programPro,
      );
    });

    test('alliance heuristic: score line keeps general', () {
      const rawText = '''
T 전화 배정 완료
배정취소
100점
카드 | 확정
24,000 P
고객 상황실
''';
      expect(
        KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          rawText,
          const <TextBlock>[],
          KakaoCallCardOcr.programGeneral,
        ),
        KakaoCallCardOcr.programGeneral,
      );
    });

    test('alliance heuristic: no score marker becomes alliance', () {
      const rawText = '''
T 전화 배정 완료
배정취소
카드 | 확정
24,000 P
고객 상황실
제휴콜
''';
      expect(
        KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          rawText,
          const <TextBlock>[],
          KakaoCallCardOcr.programGeneral,
        ),
        KakaoCallCardOcr.programAlliance,
      );
    });

    test('alliance heuristic: pro unchanged', () {
      expect(
        KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          '법인 무료보험 200점',
          const <TextBlock>[],
          KakaoCallCardOcr.programPro,
        ),
        KakaoCallCardOcr.programPro,
      );
    });

    test('general type1 basic two-line addresses and card fare', () {
      const rawText = '''
배정 완료
배정취소 메뉴
신원동
역전할머니맥주 고양신원점
경기 과천시 원문동
래미안슈르아파트 325동
100점
카드 | 확정
40,800 P
고객과 통화
고객과 메시지
고객과 만날 장소 길찾기
밀어서 고객에게 도착알림
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '신원동 역전할머니맥주 고양신원점');
      expect(parsed.endLocation, '경기 과천시 원문동 래미안슈르아파트 325동');
      expect(parsed.grossFare, 40800);
    });

    test('card fare without P suffix after confirmation', () {
      const rawText = '''
배정 완료
배정취소 메뉴
신원동
역전할머니맥주 고양신원점
경기 과천시 원문동
래미안슈르아파트 325동
100점
카드 | 확정
40,800
고객과 통화
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.grossFare, 40800);
    });

    test('card fare from noisy amount line', () {
      const rawText = '''
배정 완료
배정취소 메뉴
신원동
역전할머니맥주 고양신원점
경기 과천시 원문동
래미안슈르아파트 325동
카드 | 확정
40,8oo P
고객과 통화
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.grossFare, 40800);
    });
  });

  group('Logi/Colmanner OCR regression', () {
    test('colmanner consecutive empty headers and tabular headers (천천동 531)', () {
      const rawText = '''
8:38
위치 : 여의동/ 여의도CGV 잔액 : 51,015원
고객전화
지사명 청방(청방)
고객명 윤상혁/부문장님
출발지
도착지
출도
적요
TALK
입금합계
차감합계
고객정보
서울 영등포구 여의도동
여의도동 34-8
경기 수원시장안구 천천동
천천동 531
경로거리 : 33.8km
현금 0원
(예상소요시간 : 51분)
요금 50,000원 (예상 수익금:39,526원)
//[자택:수원천천동
상황실
비단마을현대우방아파트기15동1703호]
합계 : 50,000원
예상 후물요금: 50,000원
합계 : 11,374원
예상 운행수수료 : 10,000원
예상 고용보험료 : 219원
예상 산재보험료 : 255원
/[자택:수원천천동
비단마을현대우방아파트115동1103호]
서명
고객위치 90 출도경로
킬안내
운행 시작
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.grossFare, 50000);
      expect(parsed.startLocation, '서울 영등포구 여의도동 여의도동 34-8');
      expect(parsed.endLocation, '경기 수원시장안구 천천동 천천동 531');
    });

    test('logi multiline address with detail', () {
      const rawText = '''
요금 40000원
고객 일반 일반
출발지 금촌동
시청로240
상세:경기 파주시 금촌동 425-0 시청로 240
도착지 서울 노원구
공릉동)공릉동(동일로184길63-14
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.grossFare, 40000);
      expect(parsed.startLocation, '금촌동 시청로240 경기 파주시 금촌동 425-0 시청로 240');
      expect(parsed.endLocation, '서울 노원구 공릉동 공릉동 동일로184길63-14');
    });

    test('colmanner with waypoint label', () {
      const rawText = '''
지사명 바로콜카드대리(전국대리)
고객명 ***
출발지 서울 노원구 공릉동 동일로 1000{공릉동 617-3}
즉후)경유)카드/공릉동동일로1000/
문정동639-5번지
도착지 경기 용인시수지구 상현동
상현마을현대성우2차아파트
상현마을현대성우5차
경유지 문정동 문정동 639-5
출도 경로거리 : 51.9km
요금 55,000원 (예상 수익금:43,479원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.grossFare, 55000);
      expect(parsed.startLocation, '서울 노원구 공릉동 동일로 1000 공릉동 617-3 즉후 경유 카드 공릉동동일로1000 문정동639-5번지');
      expect(parsed.endLocation, '경기 용인시수지구 상현동 상현마을현대성우2차아파트 상현마을현대성우5차');
      expect(parsed.waypoint, '문정동 문정동 639-5');
    });

    test('logi legal call with special markers', () {
      const rawText = r'''
운행 시작
요금
25000원
입금액
5000원
고객
법인
법인명:$$(주)우리은행(별) 인천지점/지점장/조소영
출발지
ⓓ법/$청라동마당호프 2/2
상세:인천 서구 연희동 763-4 마당
도착지
인천 부평구
삼산동)삼산동삼산타운7단지아파트
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.grossFare, 25000);
      expect(parsed.startLocation, r'ⓓ법 $청라동마당호프 2 2 인천 서구 연희동 763-4 마당');
      expect(parsed.endLocation, '인천 부평구 삼산동 삼산동삼산타운7단지아파트');
    });

    test('logi destination ignores customer id and keeps address lines', () {
      const rawText = '''
요금 25000원
출발지 테스트출발
상세:경기 파주시
도착지
고객 D 8111
인천 부평구
삼산동)삼산동삼산타운7단지아파트
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.grossFare, 25000);
      expect(parsed.startLocation, '테스트출발 경기 파주시');
      expect(parsed.endLocation, '인천 부평구 삼산동)삼산동삼산타운7단지아파트');
    });

    test('logi fare from noisy amount line', () {
      const rawText = '''
요금
25ooo원
출발지 A
도착지 B
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.grossFare, 25000);
    });

    test('logi three-line departure with one-line destination after label', () {
      const rawText = '''
요금 25000원
출발지 서울 강남구 역삼동
역삼역 2번 출구
상세:서울 강남구 역삼동 123-4
도착지
경기 성남시 분당구 정자동
고객 D 8111
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(
        parsed.startLocation,
        '서울 강남구 역삼동 역삼역 2번 출구 서울 강남구 역삼동 123-4',
      );
      expect(parsed.endLocation, '경기 성남시 분당구 정자동');
    });

    test('logi two-line departure with destination before label', () {
      const rawText = '''
요금 25000원
출발지 서울 강남구 역삼동
역삼역 2번 출구
경기 성남시 분당구 정자동
도착지
고객 D 8111
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.startLocation, '서울 강남구 역삼동 역삼역 2번 출구');
      expect(parsed.endLocation, '경기 성남시 분당구 정자동');
    });

    test('logi departure only after labels with trailing destination line', () {
      const rawText = '''
요금 25000원
출발지
도착지
서울 강남구 역삼동
역삼역 2번 출구
상세:서울 강남구 역삼동 123-4
경기 성남시 분당구 정자동
고객 D 8111
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(
        parsed.startLocation,
        '서울 강남구 역삼동 역삼역 2번 출구 서울 강남구 역삼동 123-4',
      );
      expect(parsed.endLocation, '경기 성남시 분당구 정자동');
    });

    test('colmanner two-line departure with three-line destination', () {
      const rawText = '''
지사명 테스트지사
고객명 ***
출발지 경기 부천시원미구 중동 1134-5
굿모닝로얄프라자
도착지 경기 부천시오정구 여월동 7-50
여월동경기부천시오정구여월동7-50
법]부천여월.여월동7-50
출도 경로거리 : 20.5km
(예상소요시간 : 31분)
요금 35,000원 (예상 수익금:27,667원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(
        parsed.startLocation,
        '경기 부천시원미구 중동 1134-5 굿모닝로얄프라자',
      );
      expect(
        parsed.endLocation,
        '경기 부천시오정구 여월동 7-50 여월동경기부천시오정구여월동7-50 법 부천여월.여월동7-50',
      );
    });

    test('colmanner three-line departure with two-line destination', () {
      const rawText = '''
지사명 테스트지사
고객명 ***
출발지 경기 수원시장안구 영화동
킥보드x)즉후)카드/영화동
392-4예전각설렁탕
경기 광명시 소하동 1289
도착지 소하동휴먼시아304동
법]광명소하.휴먼시아304동
출도 경로거리 : 20.5km
요금 35,000원 (예상 수익금:27,667원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(
        parsed.startLocation,
        '경기 수원시장안구 영화동 392-4예전각설렁탕',
      );
      expect(
        parsed.endLocation,
        '경기 광명시 소하동 1289 소하동휴먼시아304동',
      );
    });

    test('colmanner long multiline with special symbols', () {
      const rawText = '''
지사명 드라이버인스타법인(AG콜센터)
고객명 LG전자마곡[여환국]연구위원
출발지 서울 강서구 마곡동 LG사이언스파크 ISC
⊙스타
마곡.LG사이언스파크ISC
도착지 경기 용인시기흥구 중동
성산마을신영지웰아파트 3005동
법]용인중동.동백신영지웰3005동
출도 경로거리 : 59.9km
요금 50,000원 (예상 수익금:39,526원)
현금 0원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.grossFare, 50000);
      expect(parsed.startLocation, '서울 강서구 마곡동 LG사이언스파크 ISC ⊙스타 마곡.LG사이언스파크ISC');
      expect(parsed.endLocation, '경기 용인시기흥구 중동 성산마을신영지웰아파트 3005동 법 용인중동.동백신영지웰3005동');
    });

    test('colmanner cash call keeps fare from 요금 line', () {
      const rawText = '''
지사명 주)영암.스마트쌍둥이(네트워크)
고객명 ***
출발지 경기 부천시원미구 중동 중동 1134-5
굿모닝로얄프라자
도착지 경기 부천시오정구 여월동 여월동 7-50
여월동경기부천시오정구여월동7-50
출도 경로거리 : 0km
(예상소요시간 : 13분)
적요 앱콜고객/
요금 13,000원 (예상 수익금:10,276원)
현금 13000원
입금합계 합계 : 0원
차감합계 합계 : 3,624원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.grossFare, 13000);
      expect(parsed.startLocation, '경기 부천시원미구 중동 중동 1134-5 굿모닝로얄프라자');
      expect(parsed.endLocation, '경기 부천시오정구 여월동 여월동 7-50 여월동경기부천시오정구여월동7-50');
    });

    test('colmanner multiline with emoji and special symbols', () {
      const rawText = '''
지사명 천사프리미엄2(AG콜센터)
고객명 김성철 상무
출발지 서울 영등포구 여의도동 CCMM빌딩
🌟천사
정장)비흡연)여의도.CCMM 지하5층
도착지 경기 용인시수지구 신봉동
신봉마을LG자이1차아파트
법]용인신봉.신봉마을자이1차
출도 경로거리 : 36.3km
요금 50,000원 (예상 수익금:39,526원)
현금 0원
입금합계 합계 : 50,000원
예상 후불요금 : 50,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.grossFare, 50000);
      expect(parsed.startLocation, '서울 영등포구 여의도동 CCMM빌딩 🌟천사 정장 비흡연 여의도.CCMM 지하5층');
      expect(parsed.endLocation, '경기 용인시수지구 신봉동 신봉마을LG자이1차아파트 법 용인신봉.신봉마을자이1차');
    });

    test('colmanner destination ignores customer meta and keeps address lines', () {
      const rawText = '''
요금 35000원
출발지 테스트출발
도착지
고객 D 8111
경기 광명시 소하동
소하동휴먼시아304동
출도 경로거리 : 20.5km
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.grossFare, 35000);
      expect(parsed.startLocation, '테스트출발');
      expect(parsed.endLocation, '경기 광명시 소하동 소하동휴먼시아304동');
    });

    test('logi ignores 적요 경유 and strips ui tokens', () {
      const rawText = '''
요금 50000원
출발지
도착지
대기,경유 발생시 종료후 상황실연락
상세:서울 영등포구 여의도동 20-0
LG트윈타워
인천 연수구
출발지
송도동)인천송도동.더샵마스터뷰1단지
지도
완료
배차
취소
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.waypoint, '');
      expect(parsed.startLocation, '서울 영등포구 여의도동 20-0 LG트윈타워');
      expect(parsed.endLocation, '인천 연수구 송도동)인천송도동.더샵마스터뷰1단지');
    });

    test('logi ignores 출발지 도착 pickup banner between 인천 and trailing 송도', () {
      const rawText = '''
요금 50000원
출발지
도착지
상세:서울 영등포구 여의도동 20-0
LG트윈타워
인천 연수구
출발지 도착(19분 35초)
출발지
송도동)인천송도동.더샵마스터뷰1단지
지도
완료
배차
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.startLocation, contains('여의도'));
      expect(parsed.startLocation, contains('LG트윈'));
      expect(parsed.endLocation, contains('송도'));
    });

    test('logi splits detail departure and destination before ui', () {
      const rawText = '''
요금 50000원
출발지
도착지
상세:서울 영등포구 여의도동 23-5
한화투자증권 본사
출발지
지도
인천 서구 청라동)인천청라동+청라한양수자 인레이크블루A
완료
배차
취소
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.startLocation, '서울 영등포구 여의도동 23-5 한화투자증권 본사');
      expect(parsed.endLocation, '인천 서구 청라동)인천청라동+청라한양수자 인레이크블루A');
    });

    test('logi menu header 도착지 + trailing block (user repro 광명→부천)', () {
      const rawText = r'''
00:05 00:49)
운행 시작
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
고객ID
오더번호
차량번호
경로
안내
92500093291
17분 31초 남음
30000
6000
일반 일반
0508-5068-8499
광명KTX역
[대표연합대리 010-4519-4599 00:02]
고객과의 거리: 216미터
상세:경기 광명시 일직동 276-8
광명역(15447788)
0118
1334363576
출발지
지도
경기 부천시 중동)부천신중동역푸르지오시티
완료
처리
운행시작연기
배차
취소
tl34
갱신
서명
|||
전화
전화
닫기''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.startLocation, contains('광명시'));
      expect(parsed.startLocation, anyOf(contains('광명역'), contains('광명KTX')));
      expect(parsed.endLocation, contains('부천시'));
      expect(parsed.endLocation, contains('푸르지오'));
      expect(parsed.grossFare, 30000);
    });

    test('logi gross fare ignores 입금액 stack order (6000 before 30000)', () {
      const rawText = '''
요금
입금액
17분 31초 남음
6000
30000
일반 일반
출발지
도착지
''';
      expect(LogiColmannerOcr.parseLogi(rawText).grossFare, 30000);
    });

    test('logi gross fare inferred from fee-only OCR (6000 -> 30000)', () {
      const rawText = '''
요금
입금액
고객
메모
92500093291
17분 31초 남음
6000
일반 일반
0508-5068-8499
광명KTX역
''';
      expect(LogiColmannerOcr.parseLogi(rawText).grossFare, 30000);
    });

    test('logi gross fare inferred from fee-only OCR (5000 -> 25000)', () {
      const rawText = '''
요금
입금액
18분 13초 남음
5000
일반 왕단골
출발지 A
''';
      expect(LogiColmannerOcr.parseLogi(rawText).grossFare, 25000);
    });

    test('logi lone gross amount is not multiplied (25000 stays)', () {
      const rawText = '''
요금
입금액
25000
18분 13초 남음
일반 일반
''';
      expect(LogiColmannerOcr.parseLogi(rawText).grossFare, 25000);
    });

    test('logi trims won misread on deposit (140002 -> 14000)', () {
      expect(parseLogiFareFromOcrText('140002'), 14000);
      expect(parseLogiFareFromOcrText('140002!'), 14000);
      expect(parseLogiFareFromOcrText('14002'), 14000);
    });

    test('logi fare I0000 OCR reads as 70000', () {
      expect(parseLogiFareFromOcrText('I0000'), 70000);
    });

    test('logi 서린빌딩 card: fare, departure 상세, destination 푸르지오', () {
      const rawText = r'''
요금
입금액
고객
I0000
17분 57초 남음
140002
법인
(e|I5,000/65,000/N/A)
경)서린동+SK서린빌딩B4
인천 연수구 송도동)신림역/
출발지
운행시작연기
지도
상세:서울 종로구 서린동 99-0 서린동 99
서명
완료
인천송도동+푸르지오월드마크2단지A202동
처리
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.grossFare, 70000);
      expect(parsed.startLocation, '서울 종로구 서린동 99-0');
      expect(parsed.endLocation, contains('송도'));
      expect(parsed.endLocation, contains('푸르지오'));
      expect(parsed.endLocation, isNot(contains('신림역')));
    });

    test('logi collects address after mid-card 출발지 and 지도 labels', () {
      const rawText = '''
요금 30000원
출발지
도착지
상세:경기 테스트시 출발동 1-1
건축물명
출발지
지도
경기 테스트시 도착동)도착빌딩
완료
''';
      final p = LogiColmannerOcr.parseLogi(rawText);
      expect(p.startLocation, contains('출발동'));
      expect(p.endLocation, contains('도착동'));
    });

    test('logi 상세+목동 후 마포 도착 (user repro 등촌→마포)', () {
      const rawText = r'''
23:18 iT
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
오더번호
차량번호
경로
안내
30000!
19분 20초 남음
6000
일반 40
[UE하나로(주)HnH 02-3706-1004
0508-5067-6088
23:09] 현금0.5 마일후불2.5 경유:등촌초교
고객과의 거리: 264미터
등존역 금별맥주>등존초교
6512
13344304049
출발지
지도
상세:서울 양천구 목동 609-24 금별맥주
등촌역점
서울 마포구 중동)마포중동 건영월드컵@
완료
운행시작연기
처리
서명
배차
취소
갱신
전화
전화
닫기''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.startLocation, contains('양천구'));
      expect(parsed.startLocation, contains('목동'));
      expect(parsed.endLocation, contains('마포구'));
      expect(parsed.endLocation, contains('건영'));
      expect(parsed.grossFare, 30000);
    });

    test('colmanner keeps first admin departure line after label', () {
      const rawText = '''
출발지 천사
출도
적요
도착지 후곡마을14단지아파트
경기 수원시팔달구 인계동 경기아트센터
정장)수원인계.경기아트센터게이트1
경기 고양시일산서구 일산동
법]일산후곡마을14단지
출도 경로거리 : 73.나km
요금 75,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(
        parsed.startLocation,
        '천사 경기 수원시팔달구 인계동 경기아트센터 수원인계.경기아트센터게이트1',
      );
      expect(parsed.endLocation, '후곡마을14단지아파트 경기 고양시일산서구 일산동');
    });

    test('colmanner strips route distance from destination', () {
      const rawText = '''
출발지
도착지
인천 연수구 송도동
즉후)워시갤럭시
경기 화성시 병점동
화성시 병점동 105-1
출도 경로거리 : Okm
요금 50,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, '인천 연수구 송도동');
      expect(parsed.endLocation, '경기 화성시 병점동 화성시 병점동 105-1');
    });

    test('colmanner 출도 only row after 도착지 label still collects 주소 블록', () {
      const rawText = '''
1:33
위치: 중3동/ 계남고가사거리 잔액 : 312,047원
R 고객전화
지사명 주)영암.스마트쌍둥이(L네트워크)
고객명 ***
출발지
도착지
출도
경기 부천시원미구 중동 중동 1134-5
굿모닝로얄프라자
경기 부천시오정구 여월동 여월동 7-50
차감합계
경로거리 : ㅇkm
요금 13,000원 (예상 수익금:10,276원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, contains('원미구'));
      expect(parsed.startLocation, contains('굿모닝'));
      expect(parsed.endLocation, contains('오정구'));
      expect(parsed.endLocation, contains('여월동'));
      expect(parsed.grossFare, 13000);
    });

    test('colmanner Case 12: 도화동1009 removes memo lines and processes correctly', () {
      const rawText = '''
위치 : 도화동/ 도화동1009 잔액 : 85,947원
고객전화
지사명 천사스마트(AG콜센터)
고객명 **
출발지 천사
출도
적요
도착지
인천 미추홀구 도화동
입금합계
차감합계
인천도화동1009 2-2
자택 108동 절대비흡연 전동휠킥보드절대금지
경로거리 : ㅇkm
요금 12,000원 (예상 수익금:9,289원)
현금 0원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, '천사 인천 미추홀구 도화동');
      expect(parsed.endLocation, '인천도화동1009');
      expect(parsed.grossFare, 12000);
    });

    test('colmanner Case 3: 병점동 705-1 filters 5OK payment text and preserves address', () {
      const rawText = '''
위치: 송도2동/ 투모로우시티역 잔액 : 87,821원
고객전화
지사명 서븐콜대리운전(S콜센터정산)
고객명 **
출발지
도착지
출도
인천 연수구 송도동
즉후)워시갤럭시
입금합계
차감합계
경기 화성시 병점동
그개저비
화성시 병점동 705-1
경로거리 : Okm
(예상소요시간 : 44분)
적요 대리리운전 편도요금/어플접수>출,도착지
후불5OK]완료20분후입금}카드결재
요금 50,000원 (여상 수익금:39.526원)
현금 0원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, '인천 연수구 송도동 워시갤럭시');
      expect(parsed.endLocation, '경기 화성시 병점동 화성시 병점동 705-1');
      expect(parsed.grossFare, 50000);
    });

    test('colmanner tolerates OCR spacing on 출도경로거리 stop line', () {
      const rawText = '''
출발지
도착지
서울 강남구 역삼동
건물A
경기 수원시 팔달구 행궁동
행궁동 1-1
출 도경로거리 : 40km
요금 45,000원 (예상 수익금:35,000원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, contains('역삼'));
      expect(parsed.endLocation, contains('수원'));
      expect(parsed.endLocation, isNot(contains('40km')));
      expect(parsed.grossFare, 45000);
    });

    test('colmanner 메트릭스전자담배: no 출발지 label, keep 원미구 head and full 여월 destination', () {
      const rawText = '''
지사명 메트릭스전자담배(테스트)
고객명 ***
경기 부천시원미구 중동 즉후)후불)메트릭스전자담배입구
도착지 경기 부천시오정구 여월동 여월동 7-50
출도 경로거리 : 20.5km
요금 13,000원 (예상 수익금:10,276원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, contains('부천시원미구'));
      expect(parsed.startLocation, contains('후불'));
      expect(parsed.startLocation.startsWith('후불'), isFalse);
      expect(parsed.endLocation, contains('오정구'));
      expect(parsed.endLocation, contains('여월'));
      expect(parsed.endLocation.endsWith('/0'), isFalse);
      expect(parsed.grossFare, 13000);
    });

    test('colmanner 금정동: no 도착지 label, second 경기+군포시 splits after 킥보드 noise', () {
      const rawText = '''
지사명 테스트
고객명 ***
출발지 경기 의왕시 장항동 710-1 킥보드x)카/즉후)경기 군포시 금정동 710-2
출도 경로거리 : 12km
요금 15,000원 (예상 수익금:11,800원)
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, contains('의왕시'));
      expect(parsed.startLocation, contains('장항동'));
      expect(parsed.startLocation, isNot(contains('군포시')));
      expect(parsed.startLocation, isNot(contains('금정동')));
      expect(parsed.endLocation, contains('군포시'));
      expect(parsed.endLocation, contains('금정동'));
      expect(parsed.endLocation, contains('710-2'));
    });
  });

  group('Kakao pro OCR regression', () {
    test('pro keeps second departure line with destination', () {
      const rawText = '''
배정 완료
카드 | 확정
고객
여의도동
백원
인천 중구 중산동
스카이시티자이아파트
55,800
200점
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '여의도동 백원');
      expect(parsed.endLocation, '인천 중구 중산동 스카이시티자이아파트');
      expect(parsed.grossFare, 55800);
    });

    test('pro fare ignores embedded address digits', () {
      const rawText = '''
배정 완료
카드 | 확정
고객
광주시 능평로156번길 27
서울 강남구 신사동
쉐이크섹 청담점
60,800
200점
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '광주시 능평로156번길 27');
      expect(parsed.endLocation, '서울 강남구 신사동 쉐이크섹 청담점');
      expect(parsed.grossFare, 60800);
    });
  });

  group('Kakao general OCR regression', () {
    test('strips customer call guidance from destination', () {
      const rawText = '''
배정 완료
카드 | 확정
서대문구 남가좌동 210-1
김포시 풍무동 당곡마을 3단지월드메르디앙아파
출발지에 도착하시면 도착완료 해주세요.
28,000
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.startLocation, '서대문구 남가좌동 210-1');
      expect(parsed.endLocation, '김포시 풍무동 당곡마을 3단지월드메르디앙아파');
    });
  });

  group('Logi export regression', () {
    test('keeps detail block after customer meta between empty labels', () {
      const rawText = '''
요금 30000원
출발지
도착지
고객ID
오더번호
상세:경기 광명시 일직동 276-8
광명역(15447788)
출발지
지도
경기 부천시 중동)부천신중동역푸르지오시티
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.startLocation, '경기 광명시 일직동 276-8 광명역(15447788)');
      expect(parsed.endLocation, '경기 부천시 중동)부천신중동역푸르지오시티');
    });
  });

  group('Tmap OCR regression', () {
    test('in-progress card screen parsing', () {
      const rawText = '''
고객센터
운행중
사고신고
안양시 동안구 평촌동 932 토니치킨
화성시 효행구 봉담읍 674 우방아이유쉘1단지 상가동
T 티맵으로 길안내
96%의 티맵 고객이 선호!
실수익 24,800P
운행완료
''';
      final parsed = TmapTripDetailOcr.tryParse(rawText);
      expect(parsed, isNotNull);
      expect(parsed!.startAddress, '안양시 동안구 평촌동 932 토니치킨');
      expect(parsed.endAddress, '화성시 효행구 봉담읍 674 우방아이유쉘1단지 상가동');
      expect(parsed.grossFare, 24800);
    });

    test('in-progress card screen with multiline start, end, waypoint and user real ocr', () {
      const rawText = '''
22:52 54m TALK
고객센터
운행중
부천시 원미구 중동 1257
짝궁노래바
김포시 풍무동 936
풍무센트럴푸르지오아파트15 전기차충전소
T 티맵으로 길안내
소사고신고
실수익 24,000P
운행완료
54m
677m
''';
      final parsed = TmapTripDetailOcr.tryParse(rawText);
      expect(parsed, isNotNull);
      expect(parsed!.startAddress, '부천시 원미구 중동 1257 짝궁노래바');
      expect(parsed.endAddress, '김포시 풍무동 936 풍무센트럴푸르지오아파트15 전기차충전소');
      expect(parsed.waypoint, '');
      expect(parsed.grossFare, 24000);
      expect(parsed.driveStartTimeHm, '22:52');
    });

    test('in-progress card screen with multiline start, waypoint, end and fare', () {
      const rawText = '''
고객센터
운행중
사고신고
부천시 원미구 중동 1257
짝궁노래바
인천 계양구 작전동 123
작전동경유지
김포시 풍무동 936
풍무센트럴푸르지오아파트15 전기차충전소
T 티맵으로 길안내
실수익 24,000P
''';
      final parsed = TmapTripDetailOcr.tryParse(rawText);
      expect(parsed, isNotNull);
      expect(parsed!.startAddress, '부천시 원미구 중동 1257 짝궁노래바');
      expect(parsed.waypoint, '인천 계양구 작전동 123 작전동경유지');
      expect(parsed.endAddress, '김포시 풍무동 936 풍무센트럴푸르지오아파트15 전기차충전소');
      expect(parsed.grossFare, 24000);
    });

    test('tmap driving start time fallback from first 3 lines', () {
      const rawText = '''
15:35
티맵으로 길안내
운행상세정보
실수익 24,800P
출발지 서울 종로구
도착지 경기 성남시
운행일자 2026.05.18
''';
      final parsed = TmapTripDetailOcr.tryParse(rawText);
      expect(parsed, isNotNull);
      expect(parsed!.driveStartTimeHm, '15:35');
    });
  });

  group('New OCR improvements regression tests', () {
    test('Kakao rating score 96l100/96/100/96% ignored, fare correctly parsed as 11,600', () {
      const rawText = '''
배정 완료
배정취소 메뉴
문래동3가
스트롱무브
서울 양천구 신월동
강서성결행복한홈스쿨 지역아동센터
96l100
카드 | 확정
11,600 P
고객과 통화
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.grossFare, 11600);
    });

    test('Kakao waypoint cleans standalone Q noise', () {
      const rawText = '''
배정 완료
배정취소 메뉴
출발지
풍무동 Q 경유
도착지
100점
카드 | 확정
15,000 P
''';
      final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
      expect(parsed.waypoint, '풍무동 경유');
    });

    test('Colmanner starting point strips "카" payment abbreviation', () {
      const rawText = '''
출발지 백석동 "카" 일산백석동양천리양꼬치
도착지 서울 마포구
요금 15,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, '백석동 일산백석동양천리양꼬치');
    });

    test('Colmanner waypoint resolves "그47-7" to "747-7"', () {
      const rawText = '''
출발지 서울
도착지 경기
경유지 그47-7
요금 20,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.waypoint, '747-7');
    });

    test('Colmanner start point strips "동 n후", "n후" prefix and removes situation room noise', () {
      const rawText = '''
출발지 동 n후 합정동 삼아빌딩
도착지 서울 강서구 화곡동 화곡화이트마사지
상황실 연락처 고객전화
요금 25,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.startLocation, '합정동 삼아빌딩');
      expect(parsed.endLocation, '서울 강서구 화곡동 화곡화이트마사지');
    });

    test('Colmanner waypoint correctly parses "장지동" and ignores situation room variable warning', () {
      const rawText = '''
출발지 서울
도착지 경기
경유변동시 상황실 연락 바람 경유지 장지동
요금 30,000원
''';
      final parsed = LogiColmannerOcr.parseColmanner(rawText);
      expect(parsed.waypoint, '장지동');
    });

    test('Logi waypoint strips "고객과의" distance metadata to keep "등촌초교"', () {
      const rawText = '''
요금 20000원
출발지 서울
도착지 경기
[UE하나로 23:09] 현금0.5 마일후불2.5 경유:등촌초교 고객과의 거리: 264미터
''';
      final parsed = LogiColmannerOcr.parseLogi(rawText);
      expect(parsed.waypoint, '등촌초교');
    });
  });
}


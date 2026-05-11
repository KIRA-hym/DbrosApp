import 'package:flutter_test/flutter_test.dart';

import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'package:dbros_app/utils/kakao_custom_call_ocr.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
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
  });

  group('Logi/Colmanner OCR regression', () {
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
      expect(parsed.startLocation, '금촌동 시청로240 상세:경기 파주시 금촌동 425-0 시청로 240');
      expect(parsed.endLocation, '서울 노원구 공릉동)공릉동(동일로184길63-14');
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
      expect(parsed.startLocation, '서울 노원구 공릉동 동일로 1000{공릉동 617-3} 즉후)경유)카드/공릉동동일로1000/ 문정동639-5번지');
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
      expect(parsed.startLocation, 'ⓓ법/\$청라동마당호프 2/2 상세:인천 서구 연희동 763-4 마당');
      expect(parsed.endLocation, '인천 부평구 삼산동)삼산동삼산타운7단지아파트');
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
      expect(parsed.endLocation, '경기 용인시기흥구 중동 성산마을신영지웰아파트 3005동 법]용인중동.동백신영지웰3005동');
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
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('test col', () async {
    SharedPreferences.setMockInitialValues({});
    await RemoteConfigService.init();
    
    final text = '''위치 : 초월읍 초월읍행정복지센터앞교차로 잔액 : 90,576원
고객전화
경기 광주시 초월읍쌍동리 쌍동리 394(경중대로1127번길 65
출발지 초월이-편한서세상
도착지
출도
입금합계
차감합계
즉후)경충대로112번길65.202동
고객정보
서울 동대문구 장안동 래미안장안2차아파트
상황실
연락처
R>장안래미안2차/마일~
적요 추가요금요구금지/ 접대가많은분이니** 친절부탁드려요**고객이 원하는
자리에 주차해주세요.
요금 55,000원 (예상 수익금:43,483원)
경로거리: 37.5km
현금 0원
고객위치
(예상소요시간 : 46분)
후불55K]완료20분후입금) 202동/법인아닙니다/현금요구금지/
합계 : 55,000원
예상 후불요금 : 55,000원
합계 : 12,376원
예상 운행수수료 : 11.000원
예상 고용보험료 : 239원
예상 산재보험료 : 278원
상황실
법인아닙니다/현금요구금지/추가요금요구금지/ 접대기가많은분이니**
친절부탁드려요**고객이 원하는 자리에 주차해주세요.
01045143300
접수시간 오후10:26
출도경로
운행 시작
길안내''';
    final lines = text.split('\n');
    final res = parseColmanner(lines, '요금 55,000원');
    print('START: \');
    print('END: \');
  });
}

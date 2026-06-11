import 'dart:io';
import 'lib/utils/logi_colmanner_ocr.dart';
import 'lib/services/remote_config_service.dart';

void main() {
  final lines = [
    '20:54 •',
    '위치 : 여의동/ 여의도CGV 잔액 : 259,685원',
    '고객전화',
    '출발지 서관주차장 @스타',
    '출도',
    '도착지 101동',
    '서울 영등포구 여의도동 LG트윈타워',
    '입금합계',
    '여의도.LG트윈서관지하3층',
    '경기 화성시 오산동 동탄역롯데캐슬아파트',
    '적요 /차량:179하4816',
    '상황실',
    '연락처',
    '법]화성오산동탄역롯데캐슬아파트101동',
    '경로거리 : 48.7km',
    '요금 55,000원 (예상 수익금:43,479원)',
    '현금 0원',
    '(예상소요시간 : 55분)',
    '<',
    '합계 : 55,000원',
    '예상 후불요금 : 55,000원',
    '차감합계 에사 고용보험료 : 24원',
    '합계 : 12,380원',
    '예상 운행수수료 : 11,000원',
    '고객정보 차량:119하나816',
    '상황실',
    '예상',
    '예상 산재보험료 : 280원',
    '027993311',
    '고객위치 90 출도경로',
    '서명',
    '킬안내',
    '운행 시작',
  ];

  final result = LogiColmannerOcr.parseLocations(lines, isLogi: false);
  print('Result Start: \${result.start}');
  print('Result End: \${result.end}');
}

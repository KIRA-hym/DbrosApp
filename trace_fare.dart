import 'dart:io';

void main() {
  final text = '''
SKT 3:25 T
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
닫기
  ''';
  
  final lines = text.split('\n').map((e) => e.trim()).toList();
  var inSection = false;
  final amounts = <int>[];
  
  for (final trimmed in lines) {
    if (trimmed.isEmpty) continue;
    final nk = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (nk.startsWith('요금') || nk.startsWith('입금액')) {
      inSection = true;
      continue;
    }
    if (!inSection) continue;

    final n = nk;
    final isFareClassNoise = n.startsWith('법인') || n.startsWith('현금') || n.startsWith('카드') ||
               n.startsWith('마일') || n.startsWith('선지급') || n.startsWith('착불') ||
               n.startsWith('대리') || n.startsWith('기사') || n.contains('콜마일리지') || n.contains('합계');
               
    if (isFareClassNoise) {
      print('Broke at fare class noise: $trimmed');
      if (amounts.isNotEmpty) break;
      continue;
    }
    
    if (RegExp(r'^0508-\d').hasMatch(trimmed) ||
        trimmed.contains('상세:') ||
        RegExp(r'고객과의\s*거리').hasMatch(trimmed)) {
      print('Broke at stop regex: $trimmed');
      if (amounts.isNotEmpty) break;
      continue;
    }
    
    if (nk.startsWith('입금') || nk.startsWith('차감') || nk.startsWith('수익')) continue;
    if (RegExp(r'\d{9,}').hasMatch(trimmed)) continue;

    final s = trimmed.replaceAll(RegExp(r'[,\s원]'), '');
    int? v;
    if (RegExp(r'^\d{4,6}$').hasMatch(s)) {
      final val = int.tryParse(s);
      if (val != null && val % 100 == 0) v = val;
    }
    
    if (v != null && v >= 1000 && v <= 999999 && !amounts.contains(v)) {
      amounts.add(v);
      print('Added amount: $v');
    }
  }
  
  print('Final amounts: $amounts');
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dbros_app/utils/ocr_program_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

List<TextBlock> _blocks(String raw) {
  var y = 0.0;
  final out = <TextBlock>[];
  for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    out.add(TextBlock(
      text: t,
      lines: const [],
      boundingBox: Rect.fromLTWH(0, y, 1080, 48),
      recognizedLanguages: const [],
      cornerPoints: const [],
    ));
    y += 48;
  }
  return out;
}

String? _detect(String raw) => OcrProgramDetector.detect(_blocks(raw), raw);

void main() {
  group('프로그램 판별: 실제 콜카드는 기존과 동일하게 인식 (회귀)', () {
    test('work/ocr_log_sample.txt 전체 샘플이 라벨 프로그램으로 인식됨', () {
      final f = File('work/ocr_log_sample.txt');
      if (!f.existsSync()) return;
      final parts = f.readAsStringSync().split('───────────────────────────────────────');
      var checked = 0;
      for (var i = 0; i < parts.length; i++) {
        final blk = parts[i];
        if (!blk.contains('─ RAW OCR 텍스트 ─')) continue;
        final raw = blk.split('─ RAW OCR 텍스트 ─')[1].trim();
        String? want;
        if (blk.contains('프로그램: 로지')) {
          want = '로지';
        } else if (blk.contains('프로그램: 콜마너')) {
          want = '콜마너';
        } else if (blk.contains('프로그램: 카카오')) {
          want = '카카오';
        } else if (blk.contains('프로그램: 티맵')) {
          want = '티맵';
        }
        if (want == null) continue;
        final got = _detect(raw);
        expect(got, isNotNull, reason: 'sample#${i + 1} 인식 실패');
        expect(got!.startsWith(want), isTrue,
            reason: 'sample#${i + 1} want=$want got=$got');
        checked++;
      }
      expect(checked, greaterThan(0));
    });

    test('ocr_parse_export JSON(있으면) 전체 건이 기존 라벨과 동일 프로그램으로 인식됨', () {
      final f = File(r'C:\Users\HYM\Documents\카카오톡 받은 파일\ocr_parse_export_20260515.json');
      if (!f.existsSync()) return;
      final root = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final entries = (root['entries'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final e in entries) {
        final raw = (e['raw_text'] ?? '').toString();
        final label = (e['program'] ?? '').toString();
        if (raw.trim().isEmpty || label.isEmpty) continue;
        final got = _detect(raw);
        expect(got, isNotNull, reason: 'id=${e['id']} label=$label 인식 실패');
        if (label.startsWith('카카오')) {
          expect(got!.startsWith('카카오'), isTrue, reason: 'id=${e['id']} label=$label got=$got');
        } else {
          expect(got, label, reason: 'id=${e['id']}');
        }
      }
    });

    test('카카오 운행 시작 전 화면(운행시작+배정취소)이 로지로 가로채이지 않음', () {
      const raw = '''
운행 시작 전
배정 완료
배정취소
서울 강남구 역삼동
경기 성남시 분당구
카드 | 확정
28,000 P
고객과 통화
밀어서 운행 시작
''';
      expect(_detect(raw), startsWith('카카오'));
    });

    test('콜마너 출 도경로거리 띄어쓰기 오인식도 인식', () {
      const raw = '''
출발지
도착지
서울 강남구 역삼동
경기 수원시 팔달구 행궁동
출 도경로거리 : 40km
요금 45,000원
''';
      expect(_detect(raw), '콜마너');
    });

    test('카카오 하단이 잘린 부분 캡처(배정 완료 + 카드|확정)도 인식', () {
      const raw = '''
배정 완료
카드 | 확정
고객
여의도동
백원
인천 중구 중산동
55,800
''';
      expect(_detect(raw), startsWith('카카오'));
    });

    test('카카오 상단 가림(고객과 통화 + 요금 숫자)도 인식', () {
      const raw = '''
서울 송파구 위례송파로 80
36,800
고객과 통화
''';
      expect(_detect(raw), startsWith('카카오'));
    });
  });

  group('프로그램 판별: 콜카드가 아닌 화면은 차단', () {
    test('카카오 맞춤콜 화면은 더 이상 인식하지 않음', () {
      const raw = '''
맞춤콜 프로 단독배정
출발 도보 759m(약11분)
도착 약 44분 운행
실제 수익 카드 | 확정 | 36,000 P
거절 2 초 뒤 자동수락
''';
      expect(_detect(raw), isNull);
    });

    test('단어 1개만 우연히 포함된 일반 화면: 고객과 통화', () {
      expect(_detect('고객과 통화\n최근 통화 목록'), isNull);
    });

    test('단어 1개만 우연히 포함된 일반 화면: 배차 / 갱신 / 출도', () {
      expect(_detect('오늘의 배차 뉴스 기사\n주식 시황'), isNull);
      expect(_detect('앱 업데이트 갱신 완료\n설정'), isNull);
      expect(_detect('출도 일정 안내\n메모'), isNull);
    });

    test('일반 채팅/갤러리 화면', () {
      expect(_detect('오후 3:20\n사진\n앨범\n메시지를 입력하세요'), isNull);
    });

    test('앱 내부 OCR 디버그 로그 화면은 차단', () {
      expect(_detect('✅ 자동인식 성공 로그\n카카오(일반) 28800원\n배정 완료\n고객과 통화'), isNull);
    });
  });
}

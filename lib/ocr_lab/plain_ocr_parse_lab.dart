import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/settings_service.dart';
import '../utils/kakao_call_card_ocr.dart';
import '../utils/kakao_custom_call_ocr.dart';
import '../utils/logi_colmanner_ocr.dart';
import '../utils/tmap_trip_detail_ocr.dart';

/// PC 웹 실험실: 앱에서 복사한 OCR 원문 → 앱과 동일 파서로 결과만 산출(DB·이미지 없음).
class PlainOcrParseLab {
  PlainOcrParseLab._();

  static const String snapshotKey = '_ocr_full_text_snapshot';
  static const String detectPathKey = 'program_detect_path';

  /// 줄마다 세로 배치한 합성 [TextBlock]. 카카오 Y좌표 경로는 실제 OCR과 다를 수 있음.
  static List<TextBlock> syntheticBlocksFromPlainOcrText(String fullText) {
    final blocks = <TextBlock>[];
    var y = 0.0;
    const step = 48.0;
    for (final raw in fullText.replaceAll('\r\n', '\n').split('\n')) {
      final t = raw.trim();
      if (t.isEmpty) {
        y += step * 0.35;
        continue;
      }
      blocks.add(
        TextBlock(
          text: t,
          lines: const [],
          boundingBox: Rect.fromLTWH(0, y, 1080, step),
          recognizedLanguages: const [],
          cornerPoints: const [],
        ),
      );
      y += step;
    }
    return blocks;
  }

  static String? normalizeForcedProgram(String? label) {
    if (label == null) return null;
    final s = label.trim();
    if (s.isEmpty || s == '자동') return null;
    switch (s) {
      case '콜마너':
        return '콜마너';
      case '로지':
        return '로지';
      case '티맵':
        return '티맵';
      case '카카오(커스텀)':
        return KakaoCustomCallOcr.programCustom;
      case '카카오(일반)':
        return KakaoCallCardOcr.programGeneral;
      case '카카오(프콜)':
        return KakaoCallCardOcr.programPro;
      case '카카오(제휴)':
        return KakaoCallCardOcr.programAlliance;
      default:
        return null;
    }
  }

  static ({String? program, String pathTag}) detectProgram(
    List<TextBlock> blocks,
    String fullText,
  ) {
    final normalized = fullText.replaceAll(RegExp(r'\s+'), '');
    for (final block in blocks) {
      if (block.text.contains('갱신')) return (program: '로지', pathTag: 'logi_block');
      if (block.text.contains('출도')) return (program: '콜마너', pathTag: 'colmanner_block');
    }
    if (normalized.contains('운행시작') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지') &&
        (normalized.contains('입금액') || normalized.contains('고객과의거리'))) {
      return (program: '로지', pathTag: 'logi_fulltext');
    }
    if (normalized.contains('지사명') &&
        normalized.contains('출도') &&
        normalized.contains('출발지') &&
        normalized.contains('도착지')) {
      return (program: '콜마너', pathTag: 'colmanner_fulltext');
    }
    if (TmapTripDetailOcr.isTripDetailScreen(fullText)) {
      return (program: '티맵', pathTag: 'tmap');
    }
    if (KakaoCustomCallOcr.isCustomCallScreen(fullText)) {
      return (program: KakaoCustomCallOcr.programCustom, pathTag: 'kakao_custom');
    }
    final kakao = KakaoCallCardOcr.detectKakaoProgram(fullText);
    if (kakao != null) {
      final p = KakaoCallCardOcr.refineProgramByAllianceHeuristic(fullText, blocks, kakao);
      return (program: p, pathTag: 'kakao_fulltext');
    }
    for (final block in blocks) {
      if (block.text.contains('고객과 통화')) {
        final p = KakaoCallCardOcr.refineProgramByAllianceHeuristic(
          fullText,
          blocks,
          KakaoCallCardOcr.programGeneral,
        );
        return (program: p, pathTag: 'kakao_block_fallback');
      }
    }
    return (program: null, pathTag: 'none');
  }

  static String normalizeProgramForSave(String program) {
    if (program == '카카오') return '카카오(일반)';
    if (program == KakaoCallCardOcr.programGeneral ||
        program == KakaoCallCardOcr.programPro ||
        program == KakaoCallCardOcr.programAlliance ||
        program == KakaoCustomCallOcr.programCustom) {
      return program;
    }
    return program;
  }

  static Map<String, dynamic> parse(
    String fullText, {
    String? forcedProgramLabel,
  }) {
    // 로그캣 등에서 복사할 때 포함된 리터럴 '\n' 문자를 실제 줄바꿈으로 변환
    final buffer = fullText.replaceAll(r'\n', '\n').replaceAll('\r\n', '\n').trimRight();
    final blocks = syntheticBlocksFromPlainOcrText(buffer);
    final force = normalizeForcedProgram(forcedProgramLabel);

    final det = force != null
        ? (program: force, pathTag: 'lab_forced')
        : detectProgram(blocks, buffer);

    if (det.program == null) {
      return {
        'ok': false,
        snapshotKey: buffer,
        detectPathKey: det.pathTag,
        'program': '',
        'error': '프로그램을 판별할 수 없습니다. 상단에서 콜마너·로지 등을 직접 선택해 보세요.',
        'synthetic_blocks': blocks.length,
        'report': '',
      };
    }

    final rawProgram = det.program!;
    final detectedProgram = normalizeProgramForSave(rawProgram);

    final logData = <String, dynamic>{
      'ok': true,
      'program': detectedProgram,
      'drive_date': '',
      'drive_time': '',
      'gross_fare': 0,
      'transport_cost': 0,
      'start_location': '',
      'waypoint': '',
      'end_location': '',
      'memo': '',
      detectPathKey: det.pathTag,
      snapshotKey: buffer,
      'tmap_parse_failed': false,
      'parse_exception': '',
      'synthetic_blocks': blocks.length,
    };

    try {
      if (rawProgram == KakaoCustomCallOcr.programCustom) {
        _parseKakaoCustom(blocks, logData, buffer);
      } else if (rawProgram == KakaoCallCardOcr.programGeneral ||
          rawProgram == KakaoCallCardOcr.programPro ||
          rawProgram == KakaoCallCardOcr.programAlliance) {
        _parseKakao(blocks, logData, buffer);
      } else if (rawProgram == '로지') {
        _parseLogi(blocks, logData);
      } else if (rawProgram == '콜마너') {
        _parseColmanner(blocks, logData);
      } else if (rawProgram == '티맵') {
        final r = TmapTripDetailOcr.tryParse(buffer, blocks: blocks);
        if (r == null) {
          logData['tmap_parse_failed'] = true;
        } else {
          _applyTmap(r, logData);
        }
      }
    } catch (e, st) {
      logData['ok'] = false;
      logData['parse_exception'] = '$e\n$st';
    }

    final gross = _asInt(logData['gross_fare']);
    final transport = _asInt(logData['transport_cost']);
    final fee = SettingsService.deductionFeeFromGross(gross, detectedProgram);
    final net = (gross - fee - transport).clamp(0, 999999999);
    logData['fee'] = fee;
    logData['net_income'] = net;
    logData['report'] = buildShareReport(logData);
    return logData;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static void _parseKakaoCustom(
    List<TextBlock> blocks,
    Map<String, dynamic> logData,
    String fullText,
  ) {
    final p = KakaoCustomCallOcr.parseScreen(blocks, fullText);
    if (p.driveDateYmd != null) logData['drive_date'] = p.driveDateYmd;
    if (p.driveTimeHm != null) logData['drive_time'] = p.driveTimeHm;
    logData['waypoint'] = '';
    logData['start_location'] = p.startLocation;
    logData['end_location'] = p.endLocation;
    if (p.grossFare != null) logData['gross_fare'] = p.grossFare;
    if ((p.paymentMethod ?? '').isNotEmpty) {
      final prev = (logData['memo'] ?? '').toString().trim();
      final tag = '결제방식:${p.paymentMethod}';
      logData['memo'] = prev.isEmpty ? tag : '$tag $prev';
    }
  }

  static void _parseKakao(
    List<TextBlock> blocks,
    Map<String, dynamic> logData,
    String fullText,
  ) {
    final p = KakaoCallCardOcr.parseScreen(blocks, fullText);
    if (p.driveDateYmd != null) logData['drive_date'] = p.driveDateYmd;
    if (p.driveTimeHm != null) logData['drive_time'] = p.driveTimeHm;
    logData['waypoint'] = p.waypoint;
    logData['start_location'] = p.startLocation;
    logData['end_location'] = p.endLocation;
    if (p.grossFare != null) logData['gross_fare'] = p.grossFare;
  }

  static void _parseLogi(List<TextBlock> blocks, Map<String, dynamic> logData) {
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sorted.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseLogi(full, blocks: sorted);
    if (p.driveTimeHm.isNotEmpty) logData['drive_time'] = p.driveTimeHm;
    if (p.grossFare > 0) logData['gross_fare'] = p.grossFare;
    if (p.startLocation.isNotEmpty) logData['start_location'] = p.startLocation;
    if (p.endLocation.isNotEmpty) logData['end_location'] = p.endLocation;
    if (p.waypoint.isNotEmpty) logData['waypoint'] = p.waypoint;
  }

  static void _parseColmanner(List<TextBlock> blocks, Map<String, dynamic> logData) {
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final full = sorted.map((b) => b.text.trim()).where((e) => e.isNotEmpty).join('\n');
    final p = LogiColmannerOcr.parseColmanner(full, blocks: sorted);
    if (p.driveTimeHm.isNotEmpty) logData['drive_time'] = p.driveTimeHm;
    if (p.grossFare > 0) logData['gross_fare'] = p.grossFare;
    if (p.startLocation.isNotEmpty) logData['start_location'] = p.startLocation;
    if (p.endLocation.isNotEmpty) logData['end_location'] = p.endLocation;
    if (p.waypoint.isNotEmpty) logData['waypoint'] = p.waypoint;
  }

  static void _applyTmap(TmapTripDetailParsed r, Map<String, dynamic> logData) {
    if (r.driveDateYmd.isNotEmpty) logData['drive_date'] = r.driveDateYmd;
    if (r.driveStartTimeHm.isNotEmpty) logData['drive_time'] = r.driveStartTimeHm;
    if (r.grossFare > 0) logData['gross_fare'] = r.grossFare;
    if (r.startAddress.isNotEmpty) logData['start_location'] = r.startAddress;
    if (r.endAddress.isNotEmpty) logData['end_location'] = r.endAddress;
    if (r.waypoint != null && r.waypoint!.isNotEmpty) {
      logData['waypoint'] = r.waypoint;
    }
  }

  static String buildShareReport(Map<String, dynamic> r) {
    final buf = StringBuffer();
    buf.writeln('===== OCR 텍스트 파싱 실험실 =====');
    buf.writeln('프로그램: ${r['program'] ?? ''}');
    buf.writeln('판별경로: ${r[detectPathKey] ?? ''}');
    buf.writeln('합성 블록 수: ${r['synthetic_blocks'] ?? ''}');
    if ((r['error'] ?? '').toString().isNotEmpty) {
      buf.writeln('오류: ${r['error']}');
    }
    if ((r['parse_exception'] ?? '').toString().isNotEmpty) {
      buf.writeln('파싱 예외: ${r['parse_exception']}');
    }
    if (r['tmap_parse_failed'] == true) {
      buf.writeln('티맵: tryParse 실패(형식 불일치 가능)');
    }
    buf.writeln();
    buf.writeln('── 운행일/시각');
    buf.writeln('  ${r['drive_date'] ?? ''} ${r['drive_time'] ?? ''}');
    buf.writeln('── 요금');
    buf.writeln('  총: ${r['gross_fare'] ?? 0}  공제후: ${r['net_income'] ?? ''} (수수료 ${r['fee'] ?? ''})');
    buf.writeln('── 출발');
    buf.writeln('  ${r['start_location'] ?? ''}');
    buf.writeln('── 경유');
    buf.writeln('  ${r['waypoint'] ?? ''}');
    buf.writeln('── 도착');
    buf.writeln('  ${r['end_location'] ?? ''}');
    if ((r['memo'] ?? '').toString().trim().isNotEmpty) {
      buf.writeln('── 메모');
      buf.writeln('  ${r['memo']}');
    }
    buf.writeln();
    buf.writeln('── 기대값 / 피드백 (직접 적어 주세요) ──');
    buf.writeln('  출발지 기대: ');
    buf.writeln('  도착지 기대: ');
    buf.writeln('  요금 기대: ');
    buf.writeln('  메모: ');
    buf.writeln();
    buf.writeln('── 붙여 넣은 원문 ──');
    buf.writeln(r[snapshotKey] ?? '');
    return buf.toString();
  }
}

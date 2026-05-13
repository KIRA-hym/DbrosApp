import 'dart:convert';
import 'dart:io';

import 'package:dbros_app/utils/kakao_call_card_ocr.dart';
import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analyze OCR export parsed vs saved and reparsed', () {
    const path = r'c:\Users\HYM\Documents\카카오톡 받은 파일\ocr_parse_export_20260512.json';
    final file = File(path);
    if (!file.existsSync()) {
      return;
    }

    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final entries = (root['entries'] as List<dynamic>).cast<Map<String, dynamic>>();

    var parsedSavedMismatch = 0;
    var reparsedDiff = 0;
    final flagged = <Map<String, dynamic>>[];

    for (final entry in entries) {
      final program = entry['program']?.toString() ?? '';
      final rawText = entry['raw_text']?.toString() ?? '';
      final parsed = (entry['parsed_data'] as Map<String, dynamic>?) ?? {};
      final saved = (entry['saved_drive_log'] as Map<String, dynamic>?) ?? {};

      final parsedDep = parsed['departure']?.toString() ?? '';
      final parsedDest = parsed['destination']?.toString() ?? '';
      final parsedFare = parsed['fee_amount'];
      final parsedTime = parsed['drive_time']?.toString() ?? '';
      final parsedWaypoints = (parsed['waypoints'] as List<dynamic>?) ?? const [];

      final savedDep = saved['departure']?.toString() ?? '';
      final savedDest = saved['destination']?.toString() ?? '';
      final savedFare = saved['gross_fare'];
      final savedTime = saved['drive_time']?.toString() ?? '';
      final savedWaypoints = (saved['waypoints'] as List<dynamic>?) ?? const [];

      if (parsedDep != savedDep ||
          parsedDest != savedDest ||
          parsedFare != savedFare ||
          parsedTime != savedTime ||
          parsedWaypoints.join('|') != savedWaypoints.join('|')) {
        parsedSavedMismatch++;
        // ignore: avoid_print
        print(
          'MISMATCH saved_id=${saved['id']} program=$program '
          'parsed_dep=${jsonEncode(parsedDep)} saved_dep=${jsonEncode(savedDep)} '
          'parsed_dest=${jsonEncode(parsedDest)} saved_dest=${jsonEncode(savedDest)} '
          'parsed_fare=$parsedFare saved_fare=$savedFare',
        );
      }

      final reparsed = _reparse(program, rawText);
      final changed = reparsed.$1 != parsedDep ||
          reparsed.$2 != parsedDest ||
          reparsed.$3 != parsedFare ||
          reparsed.$4 != parsedTime ||
          reparsed.$5 != parsedWaypoints.join(' ');
      if (changed) {
        reparsedDiff++;
      }

      final flags = <String>{};
      for (final field in [parsedDep, parsedDest, savedDep, savedDest]) {
        if (_hasUiNoise(field)) flags.add('ui_noise');
        if (field.contains('경로거리')) flags.add('route_distance');
        if (field == '지도' || field.contains('경로 ||')) flags.add('map_route_token');
        if (field.contains('상세:')) flags.add('detail_prefix');
      }
      if (parsedDep.isEmpty) flags.add('empty_departure');
      if (parsedDest.isEmpty) flags.add('empty_destination');
      if (parsedDep.isNotEmpty && parsedDest.isNotEmpty && parsedDep == parsedDest) {
        flags.add('same_dep_dest');
      }
      if (parsedDep.isNotEmpty &&
          parsedDest.isNotEmpty &&
          (parsedDep.contains(parsedDest) || parsedDest.contains(parsedDep))) {
        flags.add('overlap_dep_dest');
      }
      if (program.startsWith('로지') && parsedWaypoints.isNotEmpty) {
        flags.add('logi_waypoint');
      }

      if (flags.isNotEmpty || changed) {
        flagged.add({
          'id': entry['id'],
          'saved_id': saved['id'],
          'program': program,
          'flags': flags.toList()..sort(),
          'parsed_dep': parsedDep,
          'parsed_dest': parsedDest,
          'reparsed_dep': reparsed.$1,
          'reparsed_dest': reparsed.$2,
          'parsed_fare': parsedFare,
          'reparsed_fare': reparsed.$3,
          'changed': changed,
        });
      }
    }

    // ignore: avoid_print
  print('entries=${entries.length}');
    // ignore: avoid_print
  print('parsed_saved_mismatch=$parsedSavedMismatch');
    // ignore: avoid_print
  print('reparsed_vs_export_parsed_diff=$reparsedDiff');
    // ignore: avoid_print
  print('flagged=${flagged.length}');
    for (final issue in flagged) {
      // ignore: avoid_print
      print(jsonEncode(issue));
    }
  });
}

(String, String, int, String, String) _reparse(String program, String rawText) {
  if (program.startsWith('카카오')) {
    final parsed = KakaoCallCardOcr.parseScreen(const [], rawText);
    return (
      parsed.startLocation,
      parsed.endLocation,
      parsed.grossFare ?? 0,
      parsed.driveTimeHm ?? '',
      parsed.waypoint,
    );
  }
  if (program == '콜마너') {
    final parsed = LogiColmannerOcr.parseColmanner(rawText);
    return (
      parsed.startLocation,
      parsed.endLocation,
      parsed.grossFare,
      parsed.driveTimeHm,
      parsed.waypoint,
    );
  }
  final parsed = LogiColmannerOcr.parseLogi(rawText);
  return (
    parsed.startLocation,
    parsed.endLocation,
    parsed.grossFare,
    parsed.driveTimeHm,
    parsed.waypoint,
  );
}

bool _hasUiNoise(String value) {
  const tokens = [
    '완료',
    '배차',
    '안내',
    '갱신',
    '닫기',
    '처리',
    '취소',
    '지도',
    '경로',
    '출발지',
    '도착지',
    '운행시작연기',
    '서명',
  ];
  for (final token in tokens) {
    if (value.contains(token)) return true;
  }
  return false;
}

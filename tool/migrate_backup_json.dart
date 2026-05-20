// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dbros_app/utils/backup_log_row.dart';

/// 백업 JSON의 logs를 현재 앱 DB 스키마에 맞게 정규화합니다.
///
/// dart run tool/migrate_backup_json.dart [backup.json 경로]
void main(List<String> args) {
  final path = args.isNotEmpty
      ? args[0]
      : 'logs/dbros_backup_20260519_1841/backup.json';
  final file = File(path);
  if (!file.existsSync()) {
    print('파일 없음: $path');
    exit(1);
  }

  final payload = Map<String, dynamic>.from(
    jsonDecode(file.readAsStringSync()) as Map,
  );
  final logsRaw = payload['logs'];
  if (logsRaw is! List) {
    print('logs 배열이 없습니다.');
    exit(1);
  }

  final sanitized = <Map<String, dynamic>>[];
  for (final item in logsRaw) {
    if (item is! Map) {
      print('유효하지 않은 log 항목');
      exit(1);
    }
    sanitized.add(
      BackupLogRow.sanitizeForRestore(Map<String, dynamic>.from(item)),
    );
  }

  payload['logs'] = sanitized;
  payload['formatVersion'] = 4;

  final encoder = const JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(payload)}\n');

  print('정규화 완료: $path');
  print('  logs: ${sanitized.length}건');
  print('  컬럼: ${BackupLogRow.driveLogColumnOrder.join(", ")}');
}

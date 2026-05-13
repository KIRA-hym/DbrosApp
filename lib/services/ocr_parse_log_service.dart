import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db_helper.dart';

/// OCR 파싱 결과를 일자별 JSON으로 누적하고, 설정에서 단말기 Downloads 폴더로 추출한다.
class OcrParseLogService {
  OcrParseLogService._();

  static const MethodChannel _androidChannel = MethodChannel('dbros.app/today_summary');

  static const int _maxEntriesPerDay = 200;
  static const int _maxRawTextChars = 200000;

  static String _ymd(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
  }

  static String _dailyFileName(DateTime now) => 'ocr_parse_${_ymd(now)}.json';

  static String _exportFileName(DateTime now) => 'ocr_parse_export_${_ymd(now)}.json';

  static Future<Directory> _logDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'ocr_parse_logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Map<String, dynamic> parsedDataFrom({
    String departure = '',
    String destination = '',
    Iterable<String> waypoints = const [],
    int? feeAmount,
    String? paymentMethod,
    String? driveTime,
  }) {
    return {
      'departure': departure,
      'destination': destination,
      'waypoints': waypoints.where((e) => e.trim().isNotEmpty).toList(),
      'fee_amount': feeAmount,
      'payment_method': paymentMethod,
      'drive_time': driveTime,
    };
  }

  static Map<String, dynamic> parsedDataFromLogData(Map<String, dynamic> logData) {
    final waypoints = <String>[];
    final waypoint = (logData['waypoint'] as String?)?.trim() ?? '';
    if (waypoint.isNotEmpty) waypoints.add(waypoint);

    final gross = logData['gross_fare'];
    int? feeAmount;
    if (gross is int) {
      feeAmount = gross;
    } else if (gross is num) {
      feeAmount = gross.toInt();
    } else {
      feeAmount = int.tryParse(gross?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '');
    }

    return parsedDataFrom(
      departure: (logData['start_location'] as String?)?.trim() ?? '',
      destination: (logData['end_location'] as String?)?.trim() ?? '',
      waypoints: waypoints,
      feeAmount: feeAmount,
      paymentMethod: _paymentMethodFromMemo((logData['memo'] as String?)?.trim() ?? ''),
      driveTime: (logData['drive_time'] as String?)?.trim(),
    );
  }

  static String? _paymentMethodFromMemo(String memo) {
    final m = RegExp(r'결제방식:([^\n]+)').firstMatch(memo);
    if (m == null) return null;
    final value = m.group(1)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  static Map<String, dynamic> savedDriveLogFromRow(Map<String, dynamic> row) {
    final waypoints = <String>[];
    final waypoint = (row['waypoint'] as String?)?.trim() ?? '';
    if (waypoint.isNotEmpty) waypoints.add(waypoint);

    int? asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString().replaceAll(RegExp(r'[^0-9-]'), '') ?? '');
    }

    return {
      'id': row['id'],
      'work_date': (row['work_date'] as String?)?.trim(),
      'drive_date': (row['drive_date'] as String?)?.trim(),
      'drive_time': (row['drive_time'] as String?)?.trim(),
      'program': (row['program'] as String?)?.trim(),
      'gross_fare': asInt(row['gross_fare']),
      'fee': asInt(row['fee']),
      'transport_cost': asInt(row['transport_cost']),
      'waypoint_tip': asInt(row['waypoint_tip']),
      'net_income': asInt(row['net_income']),
      'departure': (row['start_location'] as String?)?.trim() ?? '',
      'destination': (row['end_location'] as String?)?.trim() ?? '',
      'waypoints': waypoints,
      'memo': (row['memo'] as String?)?.trim(),
      'image_path': (row['image_path'] as String?)?.trim(),
      'created_at': (row['created_at'] as String?)?.trim(),
      'updated_at': (row['updated_at'] as String?)?.trim(),
    };
  }

  static Future<String?> record({
    required String source,
    String? program,
    required String rawText,
    required Map<String, dynamic> parsedData,
    bool recognized = true,
  }) async {
    try {
      final now = DateTime.now();
      final dir = await _logDir();
      final file = File(p.join(dir.path, _dailyFileName(now)));

      final payload = await _readOrCreateDailyPayload(file, now);
      final entries = List<Map<String, dynamic>>.from(payload['entries'] as List);

      var text = rawText.trim();
      if (text.length > _maxRawTextChars) {
        text = text.substring(0, _maxRawTextChars);
      }

      final entryId = now.microsecondsSinceEpoch.toString();
      entries.add({
        'id': entryId,
        'captured_at': now.toIso8601String(),
        'source': source,
        'recognized': recognized,
        'program': program,
        'raw_text': text,
        'parsed_data': parsedData,
      });

      if (entries.length > _maxEntriesPerDay) {
        entries.removeRange(0, entries.length - _maxEntriesPerDay);
      }

      payload['entries'] = entries;
      payload['updated_at'] = now.toIso8601String();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      return entryId;
    } catch (_) {}
    return null;
  }

  static Future<void> attachSavedDriveLog(
    String entryId,
    Map<String, dynamic> savedRow,
  ) async {
    if (entryId.trim().isEmpty) return;
    try {
      final dir = await _logDir();
      if (!await dir.exists()) return;

      final files = await _listDailyLogFiles(dir);
      for (final file in files.reversed) {
        final payload = await _readDailyPayload(file);
        if (payload == null) continue;
        final entries = List<Map<String, dynamic>>.from(payload['entries'] as List);
        final index = entries.indexWhere((entry) => entry['id']?.toString() == entryId);
        if (index < 0) continue;

        entries[index]['saved_drive_log'] = savedDriveLogFromRow(savedRow);
        payload['entries'] = entries;
        payload['updated_at'] = DateTime.now().toIso8601String();
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(payload),
          flush: true,
        );
        return;
      }
    } catch (_) {}
  }

  static Future<List<File>> _listDailyLogFiles(Directory dir) async {
    final files = await dir
        .list()
        .where((entity) =>
            entity is File &&
            p.basename(entity.path).startsWith('ocr_parse_') &&
            p.basename(entity.path).endsWith('.json') &&
            !p.basename(entity.path).startsWith('ocr_parse_export_'))
        .cast<File>()
        .toList();
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  static Future<Map<String, dynamic>?> _readDailyPayload(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final entries = map['entries'];
      if (entries is! List) return null;
      map['entries'] = entries
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      return map;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _loadSavedDriveLogsForExport() async {
    try {
      final rows = await DriveLogDatabase.instance.getAllDriveLogsForExport();
      return rows.map(savedDriveLogFromRow).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>> _readOrCreateDailyPayload(
    File file,
    DateTime now,
  ) async {
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final entries = map['entries'];
          if (entries is List) {
            map['entries'] = entries
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            return map;
          }
        }
      } catch (_) {}
    }

    final ymd = _ymd(now);
    return {
      'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'file_date': ymd,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'entries': <Map<String, dynamic>>[],
    };
  }

  static Future<File> exportToDownload() async {
    final now = DateTime.now();
    final dir = await _logDir();
    final entries = <Map<String, dynamic>>[];
    final sourceFiles = <String>[];

    if (await dir.exists()) {
      final files = await _listDailyLogFiles(dir);

      for (final file in files) {
        sourceFiles.add(p.basename(file.path));
        final payload = await _readDailyPayload(file);
        if (payload == null) continue;
        final dailyEntries = payload['entries'];
        if (dailyEntries is! List) continue;
        for (final entry in dailyEntries) {
          if (entry is Map) {
            entries.add(Map<String, dynamic>.from(entry));
          }
        }
      }
    }

    entries.sort((a, b) {
      final aAt = DateTime.tryParse((a['captured_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = DateTime.tryParse((b['captured_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aAt.compareTo(bAt);
    });

    final savedDriveLogs = await _loadSavedDriveLogsForExport();

    final payload = {
      'exported_at': now.toIso8601String(),
      'entry_count': entries.length,
      'saved_drive_log_count': savedDriveLogs.length,
      'source_files': sourceFiles,
      'entries': entries,
      'saved_drive_logs': savedDriveLogs,
    };

    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final fileName = _exportFileName(now);
    final savedPath = await _writeExportFile(fileName, json);
    return File(savedPath);
  }

  static Future<String> _writeExportFile(String fileName, String json) async {
    if (!kIsWeb && Platform.isAndroid) {
      final path = await _androidChannel.invokeMethod<String>(
        'writeTextToPublicDownloads',
        <String, dynamic>{
          'fileName': fileName,
          'content': json,
        },
      );
      if (path == null || path.trim().isEmpty) {
        throw StateError('단말기 Downloads 폴더에 저장하지 못했습니다.');
      }
      return path;
    }

    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      throw StateError('Downloads 폴더를 사용할 수 없습니다.');
    }
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final file = File(p.join(downloadsDir.path, fileName));
    await file.writeAsString(json, flush: true);
    return file.path;
  }
}

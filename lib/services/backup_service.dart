import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/backup_log_row.dart';
import 'db_helper.dart';
import 'expense_repository.dart';
import 'settings_service.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/foundation.dart' show kIsWeb;

class BackupService {
  static String _safeFileNameFromPath(String path) {
    final p = path.trim();
    if (p.isEmpty) return '';
    return p.split(RegExp(r'[\\/]+')).last;
  }

  static void _maybeShowSnackBar(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static Map<String, dynamic> _parseJsonMap(String jsonData) {
    final decoded = jsonDecode(jsonData);
    if (decoded is! Map) {
      throw const FormatException('백업 파일 형식이 올바르지 않습니다.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static void _validateBackupPayload(Map<String, dynamic> payload) {
    if (!payload.containsKey('settings') || payload['settings'] is! Map) {
      throw const FormatException('백업 파일에 settings 정보가 없습니다.');
    }
    if (!payload.containsKey('logs') || payload['logs'] is! List) {
      throw const FormatException('백업 파일에 logs 배열이 없습니다.');
    }

    final logs = payload['logs'] as List;
    for (final item in logs) {
      if (item is! Map) {
        throw const FormatException('백업 파일에 유효하지 않은 logs 데이터가 있습니다.');
      }
    }
    if (payload.containsKey('expenseCategories')) {
      if (payload['expenseCategories'] is! List) {
        throw const FormatException('백업 파일에 expenseCategories 형식이 올바르지 않습니다.');
      }
      for (final item in payload['expenseCategories'] as List) {
        if (item is! Map) {
          throw const FormatException('백업 파일에 유효하지 않은 expenseCategories 데이터가 있습니다.');
        }
      }
    }
    if (payload.containsKey('expenseEntries')) {
      if (payload['expenseEntries'] is! List) {
        throw const FormatException('백업 파일에 expenseEntries 형식이 올바르지 않습니다.');
      }
      for (final item in payload['expenseEntries'] as List) {
        if (item is! Map) {
          throw const FormatException('백업 파일에 유효하지 않은 expenseEntries 데이터가 있습니다.');
        }
      }
    }
    final hasExpCat = payload.containsKey('expenseCategories');
    final hasExpEnt = payload.containsKey('expenseEntries');
    if (hasExpCat != hasExpEnt) {
      throw const FormatException('백업 파일에 expenseCategories와 expenseEntries가 함께 있어야 합니다.');
    }
  }

  static Future<void> _restoreExpenseIfPresent(Map<String, dynamic> payload) async {
    if (!payload.containsKey('expenseCategories') || !payload.containsKey('expenseEntries')) {
      return;
    }
    final cats = List<Map<String, dynamic>>.from(
      (payload['expenseCategories'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final ents = List<Map<String, dynamic>>.from(
      (payload['expenseEntries'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    await ExpenseRepository.replaceFromBackup(categories: cats, entries: ents);
  }

  static Future<bool> _driveLogsTableHasLegacyDateColumn(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(drive_logs)');
    return rows.any((r) => r['name']?.toString() == 'date');
  }

  static Future<void> _restoreLogsFromBackupPayload(List logsRaw) async {
    final db = await DriveLogDatabase.instance.database;
    final hasLegacyDate = await _driveLogsTableHasLegacyDateColumn(db);
    await db.transaction((txn) async {
      await txn.delete('drive_logs');
      final batch = txn.batch();
      for (final item in logsRaw) {
        var row = BackupLogRow.sanitizeForRestore(
          Map<String, dynamic>.from(item as Map),
        );
        row = BackupLogRow.withLegacyDateIfNeeded(row, hasLegacyDate);
        batch.insert('drive_logs', row);
      }
      await batch.commit(noResult: true);
    });
    await DriveLogDatabase.instance.normalizeStoredWorkDriveDates();
    await DriveLogDatabase.instance.syncCallPointsFromDriveLogs();
  }

  static String _backupFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    return 'dbros_backup_${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}.zip';
  }

  static Map<String, dynamic> _currentSettings() {
    return <String, dynamic>{
      'baseFeeRate': SettingsService.baseFeeRate,
      'insuranceType': SettingsService.insuranceType,
      'perTripInsurance': SettingsService.perTripInsurance,
      'yearlyInsurance': SettingsService.yearlyInsurance,
      'programList': SettingsService.programList,
      'showFloatingButtons': SettingsService.showFloatingButtons,
    };
  }

  static Future<({List<Map<String, dynamic>> logs, Map<String, File> images})>
      _rewriteLogsWithBundledImageRefs() async {
    final db = await DriveLogDatabase.instance.database;
    final sourceLogs = await db.query('drive_logs');
    final logs = <Map<String, dynamic>>[];
    final images = <String, File>{};
    var imageSeq = 0;

    for (final raw in sourceLogs) {
      final log = Map<String, dynamic>.from(raw);
      final pathRaw = log['image_path']?.toString() ?? '';
      final pathTrim = pathRaw.trim();
      if (pathTrim.isNotEmpty) {
        final f = File(pathTrim);
        if (await f.exists()) {
          imageSeq++;
          final key = 'img_${imageSeq.toString().padLeft(4, '0')}_${p.basename(pathTrim)}';
          images[key] = f;
          log['image_path'] = 'images/$key';
        }
      }
      logs.add(log);
    }
    return (logs: logs, images: images);
  }

  static Future<File> _writeTempBackupZipFile() async {
    final rewritten = await _rewriteLogsWithBundledImageRefs();
    final expenseCategories = await ExpenseRepository.exportCategoriesForBackup();
    final expenseEntries = await ExpenseRepository.exportEntriesForBackup();
    final payload = <String, dynamic>{
      'logs': rewritten.logs,
      'settings': _currentSettings(),
      'backupDate': DateTime.now().toIso8601String(),
      'formatVersion': 4,
      'expenseCategories': expenseCategories,
      'expenseEntries': expenseEntries,
    };
    final tempDir = await getTemporaryDirectory();
    final backupFile =
        File('${tempDir.path}/${_backupFileName(DateTime.now())}');

    final archive = Archive();
    archive.addFile(ArchiveFile.string('backup.json', jsonEncode(payload)));
    for (final entry in rewritten.images.entries) {
      final bytes = await entry.value.readAsBytes();
      archive.addFile(ArchiveFile('images/${entry.key}', bytes.length, bytes));
    }

    final encoded = ZipEncoder().encode(archive);
    await backupFile.writeAsBytes(encoded, flush: true);
    return backupFile;
  }

  static Future<void> _restoreFromBackupJson(String jsonData) async {
    final payload = _parseJsonMap(jsonData);
    _validateBackupPayload(payload);

    await _applySettingsFromBackup(payload['settings']);
    await _restoreLogsFromBackupPayload(payload['logs'] as List);
    await _restoreExpenseIfPresent(payload);
  }

  static Future<void> _restoreFromBackupZip(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final arc = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? backupJsonEntry;
    for (final f in arc.files) {
      if (!f.isFile) continue;
      if (f.name == 'backup.json') {
        backupJsonEntry = f;
        break;
      }
    }
    if (backupJsonEntry == null) {
      throw const FormatException('ZIP 안에 backup.json 파일이 없습니다.');
    }

    final payload = _parseJsonMap(utf8.decode(backupJsonEntry.content as List<int>));
    _validateBackupPayload(payload);
    final logsRaw = List<Map<String, dynamic>>.from(
      (payload['logs'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    final appDoc = await getApplicationDocumentsDirectory();
    final imageDir = Directory(p.join(appDoc.path, 'attached_images'));
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }

    final extractedMap = <String, String>{};
    for (final f in arc.files) {
      if (!f.isFile) continue;
      if (!f.name.startsWith('images/')) continue;
      final fileName = p.basename(f.name);
      final targetPath = p.join(
        imageDir.path,
        'restored_${DateTime.now().microsecondsSinceEpoch}_$fileName',
      );
      final content = f.content as List<int>;
      await File(targetPath).writeAsBytes(content, flush: true);
      extractedMap[f.name] = targetPath;
    }

    for (final log in logsRaw) {
      final rawPath = log['image_path']?.toString() ?? '';
      if (extractedMap.containsKey(rawPath)) {
        log['image_path'] = extractedMap[rawPath];
      }
    }

    await _applySettingsFromBackup(payload['settings']);
    await _restoreLogsFromBackupPayload(logsRaw);
    await _restoreExpenseIfPresent(payload);
  }

  static Future<bool> backupToLocalDevice(BuildContext context) async {
    File? backupFile;
    try {
      backupFile = await _writeTempBackupZipFile();
      
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final downloadPath = '/storage/emulated/0/Download';
      final destFile = File('$downloadPath/dbros_backup_$dateStr.zip');
      
      await backupFile.copy(destFile.path);
      
      if (!context.mounted) return true;
      _maybeShowSnackBar(context, '단말기 Downloads 폴더에 백업되었습니다.\n($destFile)');
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _maybeShowSnackBar(context, '단말기 백업 중 오류: $e');
      return false;
    } finally {
      if (backupFile != null && await backupFile.exists()) {
        try {
          await backupFile.delete();
        } catch (_) {}
      }
    }
  }

  static Future<bool> backupToDrive(BuildContext context) async {
    File? backupFile;
    try {
      backupFile = await _writeTempBackupZipFile();

      await Share.shareXFiles(
        [XFile(backupFile.path, mimeType: 'application/zip')],
        subject: p.basename(backupFile.path),
      );

      if (!context.mounted) return true;
      _maybeShowSnackBar(context, '백업 파일을 공유/드라이브에 저장할 수 있습니다.');
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _maybeShowSnackBar(context, '드라이브 백업 중 오류: $e');
      return false;
    } finally {
      Future.delayed(const Duration(seconds: 15), () async {
        try {
          if (backupFile != null && await backupFile.exists()) {
            await backupFile.delete();
          }
        } catch (_) {}
      });
    }
  }

  static Future<bool> restoreFromFilePicker(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) {
        if (!context.mounted) return false;
        _maybeShowSnackBar(context, '복원 파일 선택이 취소되었습니다.');
        return false;
      }
      final pickedPath = result.files.single.path;
      if (pickedPath == null) {
        throw const FormatException('파일 경로를 가져올 수 없습니다. 파일이 유효한지 확인해주세요.');
      }

      final fileName = _safeFileNameFromPath(pickedPath);
      final pickedFile = File(pickedPath);
      if (!(await pickedFile.exists())) {
        throw const FormatException('선택된 파일을 읽을 수 없습니다.');
      }

      final lower = pickedPath.toLowerCase();
      bool isZip = lower.endsWith('.zip');

      if (!isZip) {
        try {
          final raf = await pickedFile.open(mode: FileMode.read);
          final bytes = await raf.read(4);
          await raf.close();
          if (bytes.length >= 4 && bytes[0] == 80 && bytes[1] == 75 && bytes[2] == 3 && bytes[3] == 4) {
            isZip = true;
          }
        } catch (_) {}
      }

      if (isZip) {
        await _restoreFromBackupZip(pickedFile);
      } else {
        final jsonData = await pickedFile.readAsString();
        await _restoreFromBackupJson(jsonData);
      }

      if (!context.mounted) return false;
      _maybeShowSnackBar(
        context,
        fileName.isEmpty ? '복원이 완료되었습니다.' : '복원이 완료되었습니다: $fileName',
      );
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _maybeShowSnackBar(context, '파일 복원 중 오류: $e');
      return false;
    }
  }

  static Future<void> _applySettingsFromBackup(dynamic settingsRaw) async {
    if (settingsRaw is! Map) return;
    final s = Map<String, dynamic>.from(settingsRaw);

    if (s['baseFeeRate'] != null) {
      await SettingsService.setBaseFeeRate((s['baseFeeRate'] as num).toDouble());
    }
    if (s['insuranceType'] != null) {
      await SettingsService.setInsuranceType(s['insuranceType'].toString());
    }
    if (s['perTripInsurance'] != null) {
      await SettingsService.setPerTripInsurance((s['perTripInsurance'] as num).toInt());
    }
    if (s['yearlyInsurance'] != null) {
      await SettingsService.setYearlyInsurance((s['yearlyInsurance'] as num).toInt());
    }
    if (s['programList'] != null) {
      await SettingsService.setProgramList(List<String>.from(s['programList'] as List));
    }
    if (s['showFloatingButtons'] != null) {
      await SettingsService.setShowFloatingButtons(s['showFloatingButtons'] as bool);
    }
  }

  static const MethodChannel _androidChannel = MethodChannel('dbros.app/today_summary');

  static Future<int> purgeOldImages({String? customPeriod}) async {
    final period = customPeriod ?? SettingsService.imagePurgePeriod;
    if (period == 'none') return 0;

    final days = period == '3_months' ? 90 : 180;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final cutoffStr = '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';

    final db = await DriveLogDatabase.instance.database;
    final List<Map<String, dynamic>> targetLogs = await db.query(
      'drive_logs',
      where: 'drive_date < ? AND image_path IS NOT NULL AND TRIM(image_path) != ""',
      whereArgs: [cutoffStr],
    );

    if (targetLogs.isEmpty) return 0;

    var deletedCount = 0;
    for (final log in targetLogs) {
      final id = log['id'];
      final path = log['image_path']?.toString() ?? '';
      if (path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            deletedCount++;
          }
        } catch (_) {}
      }
      await db.update(
        'drive_logs',
        <String, Object?>{'image_path': ''},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return deletedCount;
  }

  static Future<bool> runAutoBackupIfNeeded({bool force = false}) async {
    if (!force && !SettingsService.autoBackupEnabled) return false;

    final now = DateTime.now();
    if (!force) {
      final lastBackupStr = SettingsService.lastAutoBackupDate;
      if (lastBackupStr.isNotEmpty) {
        final lastBackup = DateTime.tryParse(lastBackupStr);
        if (lastBackup != null && now.difference(lastBackup).inDays < 7) {
          return false;
        }
      }
    }

    try {
      final backupFile = await _writeTempBackupZipFile();
      final bytes = await backupFile.readAsBytes();

      if (!kIsWeb && Platform.isAndroid) {
        final dt = DateTime.now();
        final fileName = 'dbros_auto_backup_${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}.zip';
        final path = await _androidChannel.invokeMethod<String>(
          'writeBytesToPublicDownloads',
          <String, dynamic>{
            'fileName': fileName,
            'content': bytes,
            'mimeType': 'application/zip',
          },
        );
        if (path != null && path.isNotEmpty) {
          await SettingsService.setLastAutoBackupDate(now.toIso8601String());
          try {
            await backupFile.delete();
          } catch (_) {}
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

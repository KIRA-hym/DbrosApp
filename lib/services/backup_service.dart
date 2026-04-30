import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';
import 'settings_service.dart';

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
  }

  static Future<void> _restoreLogsFromBackupPayload(List logsRaw) async {
    final db = await DriveLogDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('drive_logs');
      final batch = txn.batch();
      for (final item in logsRaw) {
        batch.insert('drive_logs', Map<String, dynamic>.from(item as Map));
      }
      await batch.commit(noResult: true);
    });
  }

  static String _backupFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    return 'dbros_backup_${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}.json';
  }

  static Future<Map<String, dynamic>> _buildBackupPayload() async {
    final db = await DriveLogDatabase.instance.database;
    final List<Map<String, dynamic>> logs = await db.query('drive_logs');
    return <String, dynamic>{
      'logs': logs,
      'settings': {
        'baseFeeRate': SettingsService.baseFeeRate,
        'insuranceType': SettingsService.insuranceType,
        'perTripInsurance': SettingsService.perTripInsurance,
        'yearlyInsurance': SettingsService.yearlyInsurance,
        'programList': SettingsService.programList,
        'showFloatingButtons': SettingsService.showFloatingButtons,
      },
      'backupDate': DateTime.now().toIso8601String(),
      'formatVersion': 2,
    };
  }

  static Future<File> _writeTempBackupFile() async {
    final payload = await _buildBackupPayload();
    final tempDir = await getTemporaryDirectory();
    final backupFile =
        File('${tempDir.path}/${_backupFileName(DateTime.now())}');
    await backupFile.writeAsString(jsonEncode(payload));
    return backupFile;
  }

  static Future<void> _restoreFromBackupJson(String jsonData) async {
    final payload = _parseJsonMap(jsonData);
    _validateBackupPayload(payload);

    await _applySettingsFromBackup(payload['settings']);
    await _restoreLogsFromBackupPayload(payload['logs'] as List);
  }

  static Future<bool> backupToSelectedFile(BuildContext context) async {
    File? backupFile;
    try {
      backupFile = await _writeTempBackupFile();

      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: backupFile.path,
          mimeTypesFilter: const <String>['application/json'],
          localOnly: false,
        ),
      );

      if (savedPath == null) {
        if (!context.mounted) return false;
        _maybeShowSnackBar(context, '백업 저장이 취소되었습니다.');
        return false;
      }

      final fileName = _safeFileNameFromPath(savedPath);
      if (!context.mounted) return false;
      _maybeShowSnackBar(
        context,
        fileName.isEmpty
            ? '백업 파일을 저장했습니다.'
            : '백업 파일을 저장했습니다: $fileName',
      );
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      _maybeShowSnackBar(context, '파일 백업 중 오류: $e');
      return false;
    } finally {
      try {
        if (backupFile != null && await backupFile.exists()) {
          await backupFile.delete();
        }
      } catch (_) {}
    }
  }

  static Future<bool> restoreFromSelectedFile(BuildContext context) async {
    try {
      final pickedPath = await FlutterFileDialog.pickFile(
        params: const OpenFileDialogParams(
          fileExtensionsFilter: <String>['json'],
          mimeTypesFilter: <String>['application/json', 'text/plain'],
          localOnly: false,
          copyFileToCacheDir: true,
        ),
      );

      if (pickedPath == null) {
        if (!context.mounted) return false;
        _maybeShowSnackBar(context, '복원 파일 선택이 취소되었습니다.');
        return false;
      }

      final fileName = _safeFileNameFromPath(pickedPath);
      final pickedFile = File(pickedPath);
      if (!(await pickedFile.exists())) {
        throw const FormatException('선택된 파일을 읽을 수 없습니다.');
      }

      final jsonData = await pickedFile.readAsString();
      await _restoreFromBackupJson(jsonData);

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

}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'db_helper.dart';

class CallPointExportService {
  static Future<void> exportToCsv(BuildContext context) async {
    try {
      final db = await DriveLogDatabase.instance.database;
      final List<Map<String, dynamic>> rows = await db.query('call_points', where: 'start_lat IS NOT NULL AND start_lng IS NOT NULL');
      
      if (rows.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("추출할 좌표 데이터가 없습니다.")));
        }
        return;
      }

      List<List<dynamic>> csvData = [
        ['type', 'is_mine', 'start_location', 'start_lat', 'start_lng', 'end_location', 'drive_time', 'program', 'created_at']
      ];

      for (var row in rows) {
        csvData.add([
          row['type'] ?? '',
          row['is_mine'] ?? 0,
          row['start_location'] ?? '',
          row['start_lat'] ?? '',
          row['start_lng'] ?? '',
          row['end_location'] ?? '',
          row['drive_time'] ?? '',
          row['program'] ?? '',
          row['created_at'] ?? ''
        ]);
      }

      String csvString = csv.encode(csvData);
      
      final directory = await getApplicationDocumentsDirectory();
      final path = "${directory.path}/call_points_export_${DateTime.now().millisecondsSinceEpoch}.csv";
      final file = File(path);
      await file.writeAsString(csvString);

      if (context.mounted) {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(path)],
          text: '콜포인트 공유',
          sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("추출 중 오류가 발생했습니다: $e")));
      }
    }
  }

  static Future<void> importFromCsv(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String csvString = await file.readAsString();
        
        List<List<dynamic>> csvData = csv.decode(csvString);
        if (csvData.isEmpty || csvData.length == 1) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("파일에 데이터가 없습니다.")));
          }
          return;
        }

        final headers = csvData[0].map((e) => e.toString().trim()).toList();
        
        final db = await DriveLogDatabase.instance.database;
        int importedCount = 0;

        for (int i = 1; i < csvData.length; i++) {
          final row = csvData[i];
          if (row.length != headers.length) continue;

          Map<String, dynamic> data = {};
          for (int j = 0; j < headers.length; j++) {
            data[headers[j]] = row[j];
          }

          final type = data['type']?.toString() ?? 'reference';
          final startLat = double.tryParse(data['start_lat']?.toString() ?? '');
          final startLng = double.tryParse(data['start_lng']?.toString() ?? '');
          
          if (startLat == null || startLng == null) continue;

          if (type == 'reference') {
            // Check if exists for reference (overwrite)
            final existing = await db.query('call_points', 
              where: 'type = ? AND start_lat = ? AND start_lng = ?', 
              whereArgs: ['reference', startLat, startLng]
            );
            
            if (existing.isNotEmpty) {
              await db.update('call_points', {
                'start_location': data['start_location']?.toString() ?? '',
                'end_location': data['end_location']?.toString() ?? '',
                'drive_time': data['drive_time']?.toString() ?? '',
                'program': data['program']?.toString() ?? '',
              }, where: 'id = ?', whereArgs: [existing.first['id']]);
            } else {
              await db.insert('call_points', {
                'type': 'reference',
                'is_mine': 0,
                'start_location': data['start_location']?.toString() ?? '',
                'start_lat': startLat,
                'start_lng': startLng,
                'end_location': data['end_location']?.toString() ?? '',
                'drive_time': data['drive_time']?.toString() ?? '',
                'program': data['program']?.toString() ?? '',
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          } else {
            // type == 'log' -> share log (is_mine = 0)
            await db.insert('call_points', {
              'type': 'log',
              'is_mine': 0, // Imported log is always shared (not mine)
              'start_location': data['start_location']?.toString() ?? '',
              'start_lat': startLat,
              'start_lng': startLng,
              'end_location': data['end_location']?.toString() ?? '',
              'drive_time': data['drive_time']?.toString() ?? '',
              'program': data['program']?.toString() ?? '',
              'created_at': DateTime.now().toIso8601String(),
            });
          }
          importedCount++;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$importedCount개의 좌표 데이터를 가져왔습니다.")));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("가져오기 중 오류가 발생했습니다: $e")));
      }
    }
  }
}

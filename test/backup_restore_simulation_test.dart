import 'dart:convert';
import 'dart:io';

import 'package:dbros_app/utils/backup_log_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('restore backup.json into current drive_logs schema', () async {
    final jsonText = await File('logs/dbros_backup_20260519_1841/backup.json')
        .readAsString();
    final payload = jsonDecode(jsonText) as Map<String, dynamic>;
    final logsRaw = payload['logs'] as List;

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE drive_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            work_date TEXT,
            drive_date TEXT,
            drive_time TEXT,
            program TEXT,
            gross_fare INTEGER,
            fee INTEGER,
            transport_cost INTEGER,
            waypoint_tip INTEGER DEFAULT 0,
            net_income INTEGER,
            start_location TEXT,
            waypoint TEXT,
            end_location TEXT,
            memo TEXT,
            image_path TEXT,
            start_lat REAL,
            start_lng REAL,
            end_lat REAL,
            end_lng REAL,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      },
    );

    await db.transaction((txn) async {
      await txn.delete('drive_logs');
      final batch = txn.batch();
      for (final item in logsRaw) {
        batch.insert(
          'drive_logs',
          BackupLogRow.sanitizeForRestore(Map<String, dynamic>.from(item as Map)),
        );
      }
      await batch.commit(noResult: true);
    });

    final count =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM drive_logs'));
    expect(count, logsRaw.length);
    await db.close();
  });

  test('restore fails on legacy schema missing work_date (old installs)', () async {
    final jsonText = await File('logs/dbros_backup_20260519_1841/backup.json')
        .readAsString();
    final payload = jsonDecode(jsonText) as Map<String, dynamic>;
    final first = Map<String, dynamic>.from(payload['logs'][0] as Map);

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE drive_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drive_date TEXT,
            drive_time TEXT,
            program TEXT,
            gross_fare INTEGER,
            fee INTEGER,
            transport_cost INTEGER,
            net_income INTEGER,
            start_location TEXT,
            waypoint TEXT,
            end_location TEXT,
            memo TEXT,
            image_path TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      },
    );

    try {
      final batch = db.batch();
      batch.insert('drive_logs', first);
      await batch.commit(noResult: true);
      fail('expected DatabaseException');
    } on DatabaseException catch (e) {
      expect(e.toString(), contains('work_date'));
      // ignore: avoid_print
      print('legacy batch error sample: $e');
    }
    await db.close();
  });

  test('restore fails on hybrid schema with extra legacy date NOT NULL', () async {
    final jsonText = await File('logs/dbros_backup_20260519_1841/backup.json')
        .readAsString();
    final first = Map<String, dynamic>.from(
      (jsonDecode(jsonText) as Map)['logs'][0] as Map,
    );

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE drive_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            work_date TEXT,
            drive_date TEXT,
            drive_time TEXT,
            program TEXT,
            gross_fare INTEGER,
            fee INTEGER,
            transport_cost INTEGER,
            waypoint_tip INTEGER DEFAULT 0,
            net_income INTEGER,
            start_location TEXT,
            waypoint TEXT,
            end_location TEXT,
            memo TEXT,
            image_path TEXT,
            start_lat REAL,
            start_lng REAL,
            end_lat REAL,
            end_lng REAL,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      },
    );

    try {
      await db.insert('drive_logs', first);
      fail('expected DatabaseException');
    } on DatabaseException catch (e) {
      // ignore: avoid_print
      print('hybrid date NOT NULL error: $e');
    }
    await db.close();
  });

  test('restore fails when legacy date column is NOT NULL', () async {
    final jsonText = await File('logs/dbros_backup_20260519_1841/backup.json')
        .readAsString();
    final first = Map<String, dynamic>.from(
      (jsonDecode(jsonText) as Map)['logs'][0] as Map,
    );

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE drive_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            drive_date TEXT,
            drive_time TEXT,
            program TEXT,
            gross_fare INTEGER,
            fee INTEGER,
            transport_cost INTEGER,
            net_income INTEGER,
            start_location TEXT,
            waypoint TEXT,
            end_location TEXT,
            memo TEXT,
            image_path TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        ''');
      },
    );

    try {
      await db.insert('drive_logs', first);
      fail('expected DatabaseException');
    } on DatabaseException catch (e) {
      // ignore: avoid_print
      print('legacy date NOT NULL error: $e');
    }
    await db.close();
  });
}

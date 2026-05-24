import 'package:dbros_app/services/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('syncCallPointsFromDriveLogs rebuilds log rows from drive_logs', () async {
    final db = await DriveLogDatabase.instance.database;

    await db.delete('call_points', where: 'type = ?', whereArgs: ['log']);
    await db.insert('drive_logs', {
      'work_date': '2026-05-24',
      'drive_date': '2026-05-24',
      'drive_time': '10:00',
      'program': '카카오(일반)',
      'gross_fare': 10000,
      'fee': 0,
      'transport_cost': 0,
      'net_income': 10000,
      'start_location': '테스트 출발',
      'end_location': '테스트 도착',
      'start_lat': 37.5,
      'start_lng': 127.0,
    });

    await DriveLogDatabase.instance.syncCallPointsFromDriveLogs();

    final logCount = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM call_points WHERE type = 'log'"),
    );
    final refCount = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM call_points WHERE type = 'reference'"),
    );

    expect(logCount, 1);
    expect(refCount, greaterThan(0));

    await db.close();
  });
}

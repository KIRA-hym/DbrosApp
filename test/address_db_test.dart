import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Check DB schema', () async {
    final file = File('assets/address.db');
    if (!file.existsSync()) {
      print('File not found!');
      return;
    }
    final db = await openDatabase(file.absolute.path);
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    print('Tables: ${tables}');
    
    if (tables.isNotEmpty) {
      final tableName = tables.first['name'];
      final cols = await db.rawQuery("PRAGMA table_info('${tableName}')");
      print('Columns for ${tableName}: ${cols}');
      
      final sample = await db.rawQuery("SELECT * FROM ${tableName} LIMIT 1");
      print('Sample data: ${sample}');
    }
    await db.close();
  });
}

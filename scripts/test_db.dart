import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final dbPath = join(Directory.current.path, 'assets', 'address.db');
  
  var db = await databaseFactory.openDatabase(dbPath);
  
  print('--- 용인시 수지구 (DB 데이터) ---');
  final res5 = await db.rawQuery("SELECT full_name FROM addresses WHERE full_name LIKE '%용인시 수지구%' LIMIT 10;");
  for(final r in res5) {
    print(r['full_name']);
  }

  await db.close();
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/widgets.dart';

class AddressRepository {
  static final AddressRepository _instance = AddressRepository._internal();
  factory AddressRepository() => _instance;
  AddressRepository._internal();

  Database? _db;

  Future<void> init() async {
    if (kIsWeb) return;
    if (_db != null) return;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = join(docDir.path, 'address.db');

      final dbFile = File(dbPath);
      bool needsCopy = false;
      if (!await dbFile.exists()) {
        needsCopy = true;
      } else {
        final length = await dbFile.length();
        if (length < 10000) { // 파일 크기가 너무 작으면 덮어쓰기 (assets DB는 보통 훨씬 큼)
          needsCopy = true;
        }
      }

      if (needsCopy) {
        ByteData data = await rootBundle.load('assets/address.db');
        List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await dbFile.writeAsBytes(bytes, flush: true);
      }

      _db = await openDatabase(dbPath);
    } catch (e) {
      debugPrint('AddressRepository init error: \$e');
    }
  }

  Future<List<String>> search(String query) async {
    if (query.isEmpty) return [];

    if (kIsWeb) {
      // 웹 시뮬레이터 UI 테스트를 위한 모의(Mock) 데이터 반환
      await Future.delayed(const Duration(milliseconds: 100));
      if (query.contains('ㄱㄴ') || query.contains('강남')) {
        return ['서울 강남구 역삼동', '서울 강남구 논현동', '서울 강남구 삼성동', '서울 강남구 대치동'];
      }
      if (query.contains('판교') || query.contains('ㅍㄱ')) {
        return ['경기 성남시 분당구 판교동', '경기 성남시 분당구 백현동'];
      }
      if (query.contains('ㅇㅅ')) {
        return ['서울 강남구 역삼동', '서울 서초구 양재동'];
      }
      return ['검색 결과: \$query 1', '검색 결과: \$query 2'];
    }

    if (_db == null) await init();
    if (_db == null) return []; // init 실패 시
    
    try {
      final isChosung = RegExp(r'^[ㄱ-ㅎ\s]+$').hasMatch(query);
      
      const String orderByClause = '''
        CASE 
          WHEN full_name LIKE '서울%' THEN 1 
          WHEN full_name LIKE '경기%' THEN 2 
          WHEN full_name LIKE '인천%' THEN 3 
          ELSE 4 
        END ASC, full_name ASC
      ''';
      
      List<Map<String, dynamic>> results;
      if (isChosung) {
        final cleanQuery = query.replaceAll(' ', '');
        results = await _db!.query(
          'addresses',
          columns: ['full_name'],
          where: "REPLACE(cho_seong, ' ', '') LIKE ?",
          whereArgs: ['%$cleanQuery%'],
          orderBy: orderByClause,
          limit: 20,
        );
      } else {
        final cleanQuery = query.replaceAll(' ', '');
        results = await _db!.query(
          'addresses',
          columns: ['full_name'],
          where: "REPLACE(full_name, ' ', '') LIKE ?",
          whereArgs: ['%$cleanQuery%'],
          orderBy: orderByClause,
          limit: 20,
        );
      }
      
      return results.map((row) => row['full_name'] as String).toList();
    } catch (e) {
      debugPrint('AddressRepository search error: \$e');
      return [];
    }
  }
}

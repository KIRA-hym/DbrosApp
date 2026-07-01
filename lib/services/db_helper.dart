import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:dbros_app/data/default_call_points.dart';

import 'package:intl/intl.dart';
import '../utils/drive_time_format.dart';
import '../utils/geocoding_utils.dart';
import '../utils/work_date_utils.dart';

class DriveLogDatabase {
  DriveLogDatabase._();
  static final DriveLogDatabase instance = DriveLogDatabase._();
  Database? _db;

  /// 일지 저장·삭제 후 호출 (고정 알림 갱신 등).
  static void Function()? afterLogsChanged;

  static List<Map<String, dynamic>> _mockLogsAllForWeb() {
    final now = DateTime.now();
    final List<Map<String, dynamic>> logs = [];
    int idCounter = 1;

    // 현재 날짜로부터 과거 30일간의 데이터를 생성
    for (int i = 0; i <= 30; i++) {
      final targetDate = now.subtract(Duration(days: i));
      final ymd = "${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      
      // 일요일은 휴무 (데이터 생성 안 함)
      if (targetDate.weekday == DateTime.sunday) continue;

      // 매일 2~4개의 일지 생성
      int dailyCalls = (targetDate.day % 3) + 2; 

      for (int j = 0; j < dailyCalls; j++) {
        // 시간대는 저녁 8시 ~ 새벽 1시 사이로 랜덤하게 분산 (단순 계산)
        int hour = 20 + j;
        if (hour >= 24) hour -= 24;
        final timeStr = "${hour.toString().padLeft(2, '0')}:${(j * 15 + targetDate.day % 10).toString().padLeft(2, '0')}";
        
        final programs = ['카카오(일반)', '로지', '콜마너', '카카오(제휴)'];
        final program = programs[(i + j) % programs.length];

        int grossFare = 20000 + ((i + j) % 5) * 10000;
        int fee = (grossFare * 0.2).toInt();
        int transportCost = j == dailyCalls - 1 ? 3000 : 0; // 마지막 콜 후 복귀 수단
        int tip = j == 1 ? 5000 : 0; // 간혹 경유팁 발생
        int netIncome = grossFare + tip - fee - transportCost;

        logs.add({
          'id': idCounter++, 
          'work_date': ymd, 
          'drive_date': ymd, 
          'drive_time': timeStr,
          'program': program, 
          'gross_fare': grossFare, 
          'fee': fee, 
          'transport_cost': transportCost, 
          'waypoint_tip': tip, 
          'net_income': netIncome,
          'start_location': '서울 강남구 역삼동', 
          'waypoint': tip > 0 ? '서울 서초구 서초동' : '', 
          'end_location': '경기 성남시 분당구',
          'start_lat': 37.5006, 
          'start_lng': 127.0364, 
          'end_lat': 37.3827, 
          'end_lng': 127.1189,
        });
      }
    }
    return logs;
  }

  /// 웹 목업: 실제 DB 조회와 같이 [workDateYmd]·[yearMonth]·기간으로 필터.
  static List<Map<String, dynamic>> _mockLogsForWeb({
    String? workDateYmd,
    String? driveDateYmd,
    String? yearMonth,
    String? startYmd,
    String? endYmd,
  }) {
    var list = _mockLogsAllForWeb();
    if (workDateYmd != null) {
      list = list.where((e) => e['work_date'] == workDateYmd).toList();
    }
    if (driveDateYmd != null) {
      list = list.where((e) => e['drive_date'] == driveDateYmd).toList();
    }
    if (yearMonth != null) {
      list = list.where((e) => (e['work_date'] as String).startsWith(yearMonth)).toList();
    }
    if (startYmd != null && endYmd != null) {
      list = list
          .where((e) {
            final w = e['work_date'] as String;
            return w.compareTo(startYmd) >= 0 && w.compareTo(endYmd) <= 0;
          })
          .toList();
    }
    return list;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final String dbPath = await getDatabasesPath();
    final String path = p.join(dbPath, "drive_logs.db");
    return openDatabase(
      path,
      version: 12,
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
            registration_source TEXT,
            start_lat REAL,
            start_lng REAL,
            end_lat REAL,
            end_lng REAL,
            created_at TEXT,
            updated_at TEXT,
            expense_category TEXT,
            income_category TEXT,
            insurance_fee INTEGER DEFAULT 0
          )
        ''');
        await _ensureDriveLogsSchema(db);
        await _ensureExpenseTables(db);
        await _ensureCallPointsTable(db);
        await _ensureLocalNoticesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE drive_logs ADD COLUMN waypoint_tip INTEGER DEFAULT 0');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE drive_logs ADD COLUMN work_date TEXT');
          await db.execute('UPDATE drive_logs SET work_date = drive_date WHERE work_date IS NULL OR TRIM(work_date) = \'\' ');
        }
        if (oldVersion < 4) {
          await db.execute("UPDATE drive_logs SET program = '카카오(일반)' WHERE program = '카카오'");
        }
        if (oldVersion < 5) {
          await _ensureDriveLogsSchema(db);
        }
        if (oldVersion < 6) {
          await _ensureExpenseTables(db);
        }
        if (oldVersion < 7) {
          await _ensureDriveLogsSchema(db);
        }
        if (oldVersion < 8) {
          await _ensureCallPointsTable(db);
          await db.execute('''
            INSERT INTO call_points (type, is_mine, start_location, start_lat, start_lng, end_location, drive_time, program, created_at, log_id)
            SELECT 'log', 1, start_location, start_lat, start_lng, end_location, drive_time, program, created_at, id 
            FROM drive_logs 
            WHERE start_lat IS NOT NULL AND start_lng IS NOT NULL
          ''');
        }
        if (oldVersion < 9) {
          await _ensureLocalNoticesTable(db);
        }
        if (oldVersion < 10) {
          try {
            await db.execute('ALTER TABLE local_notices ADD COLUMN is_read INTEGER DEFAULT 0');
          } catch (_) {}
        }
        if (oldVersion < 11) {
          try {
            await db.execute('ALTER TABLE drive_logs ADD COLUMN expense_category TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE drive_logs ADD COLUMN income_category TEXT');
          } catch (_) {}
        }
        if (oldVersion < 12) {
          try {
            await db.execute('ALTER TABLE drive_logs ADD COLUMN insurance_fee INTEGER DEFAULT 0');
          } catch (_) {}
        }
      },
      onOpen: (db) async {
        // 일부 기존 설치본은 버전/스키마가 불일치할 수 있어 실행 시점에 자체 복구.
        await _ensureDriveLogsSchema(db);
        await _ensureExpenseTables(db);
        await _ensureCallPointsTable(db);
        await _ensureLocalNoticesTable(db);
        await _ensureDailyWorkSessionsTable(db);
        await _migrateExpenseDates(db);
      },
    );
  }

  Future<void> _ensureLocalNoticesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_notices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        body TEXT,
        received_at TEXT,
        is_read INTEGER DEFAULT 0
      )
    ''');
    try {
      await db.execute('ALTER TABLE local_notices ADD COLUMN is_read INTEGER DEFAULT 0');
    } catch (_) {}
  }

  Future<void> _ensureDailyWorkSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_work_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_date TEXT NOT NULL UNIQUE,
        clock_in_time TEXT,
        clock_out_time TEXT,
        total_seconds INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _ensureExpenseTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_date TEXT NOT NULL,
        written_at TEXT NOT NULL,
        category_id INTEGER,
        category_name TEXT NOT NULL,
        amount INTEGER NOT NULL,
        memo TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (category_id) REFERENCES expense_categories (id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _migrateExpenseDates(Database db) async {
    try {
      final rows = await db.query('expense_entries');
      for (final row in rows) {
        final id = row['id'] as int;
        final expenseDate = row['expense_date'] as String;
        final writtenAtStr = row['written_at'] as String;

        try {
          final writtenAt = DateTime.parse(writtenAtStr);
          final expectedYmd = DateFormat('yyyy-MM-dd').format(writtenAt);
          // 입력 날짜가 현재 달력 날짜(기본값)로 그대로 저장되었을 경우 (새벽 시간대 입력 등)
          if (expenseDate == expectedYmd) {
            final effectiveYmd = WorkDateUtils.effectiveWorkDateYmd(writtenAt);
            if (effectiveYmd != expenseDate) {
              await db.update(
                'expense_entries',
                {'expense_date': effectiveYmd},
                where: 'id = ?',
                whereArgs: [id],
              );
            }
          }
        } catch (_) {
          // 파싱 에러 무시
        }
      }
    } catch (e) {
      debugPrint('Expense migration error: $e');
    }
  }


  /// `drive_logs`에 좌표가 있는 일지를 `call_points`(type=log)와 동기화합니다.
  /// 백업 복원·스키마 복구 시 사용합니다.
  Future<void> syncCallPointsFromDriveLogs() async {
    if (kIsWeb) return;
    final db = await database;
    await db.delete('call_points', where: 'type = ?', whereArgs: ['log']);
    await db.execute('''
      INSERT INTO call_points (type, is_mine, start_location, start_lat, start_lng, end_location, drive_time, program, created_at, log_id)
      SELECT 'log', 1, start_location, start_lat, start_lng, end_location, drive_time, program, created_at, id
      FROM drive_logs
      WHERE start_lat IS NOT NULL AND start_lng IS NOT NULL
    ''');
  }

  Future<void> _ensureCallPointsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS call_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        is_mine INTEGER NOT NULL,
        start_location TEXT,
        start_lat REAL,
        start_lng REAL,
        end_location TEXT,
        drive_time TEXT,
        program TEXT,
        created_at TEXT,
        log_id INTEGER,
        user_id TEXT,
        gross_fare INTEGER DEFAULT 0,
        waypoint TEXT,
        memo TEXT
      )
    ''');
    
    // Ensure log_id, user_id, gross_fare, waypoint columns exist for older installations
    final List<Map<String, Object?>> rows = await db.rawQuery("PRAGMA table_info(call_points)");
    if (rows.isNotEmpty) {
      final columns = rows.map((r) => r['name'].toString()).toSet();
      if (!columns.contains('log_id')) {
        await db.execute('ALTER TABLE call_points ADD COLUMN log_id INTEGER');
      }
      if (!columns.contains('user_id')) {
        await db.execute('ALTER TABLE call_points ADD COLUMN user_id TEXT');
      }
      if (!columns.contains('gross_fare')) {
        await db.execute('ALTER TABLE call_points ADD COLUMN gross_fare INTEGER DEFAULT 0');
      }
      if (!columns.contains('waypoint')) {
        await db.execute('ALTER TABLE call_points ADD COLUMN waypoint TEXT');
      }
      if (!columns.contains('memo')) {
        await db.execute('ALTER TABLE call_points ADD COLUMN memo TEXT');
      }
      
      // 기존에 존재하는 콜포인트의 user_id를 'admin'으로 초기화
      await db.execute("UPDATE call_points SET user_id = 'admin' WHERE type = 'reference' AND user_id IS NULL");
    }
    
    // Seed reference data if none exists or if it's the old short list
    final refCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM call_points WHERE type IN ('reference', 'restroom', 'shuttle')")) ?? 0;
    if (refCount < 500) {
      await db.execute("DELETE FROM call_points WHERE type IN ('reference', 'restroom', 'shuttle')");
      try {
        final batch = db.batch();
        for (var r in defaultCallPoints) {
          batch.insert('call_points', {
            'type': r['type'],
            'is_mine': 0,
            'start_location': r['start_location'],
            'start_lat': r['start_lat'],
            'start_lng': r['start_lng'],
            'user_id': r['user_id'],
            'memo': r['memo'],
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
      } catch (e) {
        if (kDebugMode) print('[DB] call_points seeding error: $e');
      }
    }
  }

  Future<void> _ensureDriveLogsSchema(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery("PRAGMA table_info(drive_logs)");
    if (rows.isEmpty) return;
    final Set<String> columns = rows
        .map((r) => (r['name']?.toString() ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet();

    Future<void> addIfMissing(String column, String definition) async {
      if (columns.contains(column)) return;
      await db.execute('ALTER TABLE drive_logs ADD COLUMN $column $definition');
      columns.add(column);
    }

    await addIfMissing('work_date', 'TEXT');
    await addIfMissing('drive_date', 'TEXT');
    await addIfMissing('waypoint_tip', 'INTEGER DEFAULT 0');
    await addIfMissing('start_lat', 'REAL');
    await addIfMissing('start_lng', 'REAL');
    await addIfMissing('end_lat', 'REAL');
    await addIfMissing('end_lng', 'REAL');
    await addIfMissing('registration_source', 'TEXT');
    await addIfMissing('expense_category', 'TEXT');
    await addIfMissing('income_category', 'TEXT');
    await addIfMissing('insurance_fee', 'INTEGER DEFAULT 0');

    if (!columns.contains('drive_date') && columns.contains('date')) {
      await db.execute("ALTER TABLE drive_logs ADD COLUMN drive_date TEXT");
      columns.add('drive_date');
    }
    if (columns.contains('date')) {
      await db.execute(
        "UPDATE drive_logs SET drive_date = date "
        "WHERE (drive_date IS NULL OR TRIM(drive_date) = '') AND date IS NOT NULL",
      );
      await db.execute(
        "UPDATE drive_logs SET work_date = COALESCE(work_date, date) "
        "WHERE (work_date IS NULL OR TRIM(work_date) = '') AND date IS NOT NULL",
      );
    }
    await normalizeStoredWorkDriveDates(db);
  }

  /// 기존 행: `work_date`/`drive_date` 한쪽만 있으면 반대쪽에 복사.
  Future<void> normalizeStoredWorkDriveDates([Database? db]) async {
    final d = db ?? await database;
    await d.execute(
      "UPDATE drive_logs SET work_date = drive_date "
      "WHERE (work_date IS NULL OR TRIM(work_date) = '') AND drive_date IS NOT NULL AND TRIM(drive_date) != ''",
    );

    final missingDrive = await d.rawQuery(
      '''
      SELECT id, work_date, drive_time FROM drive_logs
      WHERE (drive_date IS NULL OR TRIM(drive_date) = '')
        AND work_date IS NOT NULL AND TRIM(work_date) != ''
      ''',
    );
    for (final r in missingDrive) {
      final id = r['id'];
      if (id == null) continue;
      final w = (r['work_date'] ?? '').toString().trim();
      if (w.isEmpty) continue;
      final t = resolveDriveTimeForStorage(r['drive_time']?.toString());
      final dr = WorkDateUtils.resolveDriveDateForNightShift(w, t);
      await d.update(
        'drive_logs',
        <String, Object?>{'drive_date': dr, 'drive_time': t},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    final orphans = await d.rawQuery(
      '''
      SELECT id, drive_time, created_at FROM drive_logs
      WHERE (work_date IS NULL OR TRIM(work_date) = '')
        AND (drive_date IS NULL OR TRIM(drive_date) = '')
      ''',
    );
    for (final r in orphans) {
      final id = r['id'];
      if (id == null) continue;
      final created = DateTime.tryParse((r['created_at'] ?? '').toString());
      final w = WorkDateUtils.effectiveWorkDateYmd(created ?? DateTime.now());
      final t = resolveDriveTimeForStorage(r['drive_time']?.toString());
      final dr = WorkDateUtils.resolveDriveDateForNightShift(w, t);
      await d.update(
        'drive_logs',
        <String, Object?>{'work_date': w, 'drive_date': dr, 'drive_time': t},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// 저장 시 `work_date`·`drive_date`·`drive_time`이 비지 않도록 보정.
  /// 근무일만 있고 운행일이 비면 → 새벽 규칙으로 운행일 산출(단순 동일 복사 아님).
  static void ensureNonEmptyWorkDriveDatesInPlace(Map<String, dynamic> row) {
    var w = (row['work_date']?.toString() ?? '').trim();
    var d = (row['drive_date']?.toString() ?? '').trim();
    final timeHm = resolveDriveTimeForStorage(row['drive_time']?.toString());
    row['drive_time'] = timeHm;

    if (w.isEmpty && d.isNotEmpty) {
      w = d;
    } else if (w.isNotEmpty && d.isEmpty) {
      d = WorkDateUtils.resolveDriveDateForNightShift(w, timeHm);
    } else if (w.isEmpty && d.isEmpty) {
      w = WorkDateUtils.effectiveWorkDateYmd();
      d = WorkDateUtils.resolveDriveDateForNightShift(w, timeHm);
    }
    row['work_date'] = w;
    row['drive_date'] = d;
  }

  Future<int> insertOrUpdateDriveLog(Map<String, dynamic> row) async {
    final db = await database;
    final out = Map<String, dynamic>.from(row);
    ensureNonEmptyWorkDriveDatesInPlace(out);

    // 자동 좌표 추출 (좌표가 비어있고, 주소가 있는 경우에만 실행)
    if (!kIsWeb) {
      final startLocStr = out['start_location']?.toString().trim() ?? '';
      if (startLocStr.isNotEmpty && (out['start_lat'] == null || out['start_lng'] == null)) {
        try {
          final loc = await GeocodingUtils.getCoordinateFromAddressFallback(startLocStr);
          if (loc != null) {
            out['start_lat'] = loc.latitude;
            out['start_lng'] = loc.longitude;
          }
        } catch (_) {}
      }

      final endLocStr = out['end_location']?.toString().trim() ?? '';
      if (endLocStr.isNotEmpty && (out['end_lat'] == null || out['end_lng'] == null)) {
        try {
          final loc = await GeocodingUtils.getCoordinateFromAddressFallback(endLocStr);
          if (loc != null) {
            out['end_lat'] = loc.latitude;
            out['end_lng'] = loc.longitude;
          }
        } catch (_) {}
      }
    }

    final int result;
    if (out.containsKey('id') && out['id'] != null) {
      result = await db.update('drive_logs', out, where: 'id = ?', whereArgs: [out['id']]);
      
      // Update call_points
      if (!kIsWeb && out['start_lat'] != null && out['start_lng'] != null) {
        final existing = await db.query('call_points', where: 'log_id = ? AND type = ?', whereArgs: [out['id'], 'log']);
        if (existing.isNotEmpty) {
          await db.update('call_points', {
            'start_location': out['start_location'],
            'start_lat': out['start_lat'],
            'start_lng': out['start_lng'],
            'end_location': out['end_location'],
            'drive_time': out['drive_time'],
            'program': out['program'],
          }, where: 'log_id = ? AND type = ?', whereArgs: [out['id'], 'log']);
        } else {
          await db.insert('call_points', {
            'type': 'log',
            'is_mine': 1,
            'log_id': out['id'],
            'start_location': out['start_location'],
            'start_lat': out['start_lat'],
            'start_lng': out['start_lng'],
            'end_location': out['end_location'],
            'drive_time': out['drive_time'],
            'program': out['program'],
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      } else if (!kIsWeb && (out['start_lat'] == null || out['start_lng'] == null)) {
        await db.delete('call_points', where: 'log_id = ? AND type = ?', whereArgs: [out['id'], 'log']);
      }
    } else {
      result = await db.insert("drive_logs", out, conflictAlgorithm: ConflictAlgorithm.replace);
      
      // Insert into call_points
      if (!kIsWeb && out['start_lat'] != null && out['start_lng'] != null) {
        await db.insert('call_points', {
          'type': 'log',
          'is_mine': 1,
          'log_id': result,
          'start_location': out['start_location'],
          'start_lat': out['start_lat'],
          'start_lng': out['start_lng'],
          'end_location': out['end_location'],
          'drive_time': out['drive_time'],
          'program': out['program'],
          'created_at': out['created_at'] ?? DateTime.now().toIso8601String(),
        });
      }
    }
    
    // Sync insurance_fee to expense_entries
    final int logId = out['id'] ?? result;
    final int insFee = (out['insurance_fee'] as num?)?.toInt() ?? 0;
    final String memoTag = '[자동보험료] log_id:$logId';
    if (insFee > 0) {
      final existingExpense = await db.query('expense_entries', where: "memo LIKE ?", whereArgs: ["%$memoTag%"]);
      if (existingExpense.isNotEmpty) {
        await db.update('expense_entries', {
          'amount': insFee,
          'expense_date': out['drive_date'],
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [existingExpense.first['id']]);
      } else {
        await db.insert('expense_entries', {
          'expense_date': out['drive_date'],
          'written_at': DateTime.now().toIso8601String(),
          'category_name': '보험료',
          'amount': insFee,
          'memo': memoTag,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        
        // Ensure category exists
        final existingCat = await db.query('expense_categories', where: "name = ?", whereArgs: ['보험료']);
        if (existingCat.isEmpty) {
          final maxRow = await db.rawQuery('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM expense_categories');
          final ord = (maxRow.first['n'] as num?)?.toInt() ?? 0;
          await db.insert('expense_categories', {'name': '보험료', 'sort_order': ord});
        }
      }
    } else {
      await db.delete('expense_entries', where: "memo LIKE ?", whereArgs: ["%$memoTag%"]);
    }
    
    afterLogsChanged?.call();
    return result;
  }

  Future<List<Map<String, dynamic>>> getRecentLogs({int limit = 10}) async {
    if (kIsWeb) return _mockLogsAllForWeb().reversed.take(limit).toList();
    final db = await database;
    return db.query('drive_logs', orderBy: 'work_date DESC, drive_date DESC, drive_time DESC', limit: limit);
  }

  Future<int> getTotalInsuranceFee(String month) async {
    final db = await database;
    final res = await db.rawQuery('''
      SELECT SUM(insurance_fee) as total
      FROM drive_logs
      WHERE work_date LIKE ?
    ''', ['$month-%']);
    return (res.first['total'] as int?) ?? 0;
  }

  // --- Daily Work Sessions ---

  final Map<String, Map<String, dynamic>> _mockDailyWorkSessions = {};

  Future<Map<String, dynamic>?> getDailyWorkSession(String workDate) async {
    if (kIsWeb) return _mockDailyWorkSessions[workDate];
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'daily_work_sessions',
      where: 'work_date = ?',
      whereArgs: [workDate],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> saveDailyWorkSession({
    required String workDate,
    required int totalSeconds,
    required String clockInTime,
    required String clockOutTime,
  }) async {
    if (kIsWeb) {
      _mockDailyWorkSessions[workDate] = {
        'work_date': workDate,
        'clock_in_time': clockInTime,
        'clock_out_time': clockOutTime,
        'total_seconds': totalSeconds,
      };
      return;
    }
    final db = await database;
    await db.insert(
      'daily_work_sessions',
      {
        'work_date': workDate,
        'clock_in_time': clockInTime,
        'clock_out_time': clockOutTime,
        'total_seconds': totalSeconds,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDailyWorkSession(String workDate) async {
    if (kIsWeb) {
      _mockDailyWorkSessions.remove(workDate);
      return;
    }
    final db = await database;
    await db.delete(
      'daily_work_sessions',
      where: 'work_date = ?',
      whereArgs: [workDate],
    );
  }

  Future<List<Map<String, dynamic>>> getLogsForMostRecentWorkDate() async {
    if (kIsWeb) return _mockLogsAllForWeb();
    final db = await database;
    final maxDateRow = await db.rawQuery(
      'SELECT MAX(work_date) as max_date FROM drive_logs WHERE work_date IS NOT NULL AND TRIM(work_date) != ""'
    );
    if (maxDateRow.isEmpty || maxDateRow.first['max_date'] == null) {
      return [];
    }
    final maxDate = maxDateRow.first['max_date'] as String;
    return db.query(
      'drive_logs',
      where: 'work_date = ?',
      whereArgs: [maxDate],
      orderBy: 'drive_date DESC, drive_time DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllDriveLogsForExport() async {
    if (kIsWeb) return _mockLogsAllForWeb();
    final db = await database;
    return db.query(
      'drive_logs',
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getRecentLogsByDriveDateTime({int limit = 10}) async {
    if (kIsWeb) return _mockLogsAllForWeb().reversed.take(limit).toList();
    final db = await database;
    return db.query('drive_logs', orderBy: 'drive_date DESC, drive_time DESC', limit: limit);
  }

  /// 운행일(`drive_date`) 기준: 수입 = gross + waypoint_tip, 지출 = fee + transport
  Future<Map<String, int>> getTodayIncomeExpense(String driveDateYmd) async {
    if (kIsWeb) {
      final logs = _mockLogsForWeb(driveDateYmd: driveDateYmd);
      return {
        'income': logs.fold(0, (s, e) => s + (e['gross_fare'] as int)),
        'expense': logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int)),
      };
    }
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(gross_fare + COALESCE(waypoint_tip, 0)), 0) AS income,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) AS expense
      FROM drive_logs WHERE drive_date = ?
      ''',
      [driveDateYmd],
    );
    if (rows.isEmpty) {
      return {'income': 0, 'expense': 0};
    }
    final r = rows.first;
    return {
      'income': (r['income'] as num?)?.toInt() ?? 0,
      'expense': (r['expense'] as num?)?.toInt() ?? 0,
    };
  }

  /// 근무일(`work_date`) 기준: 수입 = gross + waypoint_tip, 지출 = fee + transport
  Future<Map<String, int>> getTodayIncomeExpenseByWorkDate(String workDateYmd) async {
    if (kIsWeb) {
      final logs = _mockLogsForWeb(workDateYmd: workDateYmd);
      return {
        'income': logs.fold(0, (s, e) => s + (e['gross_fare'] as int)),
        'expense': logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int)),
      };
    }
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(gross_fare + COALESCE(waypoint_tip, 0)), 0) AS income,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) AS expense
      FROM drive_logs WHERE work_date = ?
      ''',
      [workDateYmd],
    );
    if (rows.isEmpty) {
      return {'income': 0, 'expense': 0};
    }
    final r = rows.first;
    return {
      'income': (r['income'] as num?)?.toInt() ?? 0,
      'expense': (r['expense'] as num?)?.toInt() ?? 0,
    };
  }

  /// 운행일(`drive_date`) 기준. 총 매출(gross 키) = 요금+경유팁 합.
  Future<int> getTotalLogCount() async {
    final db = await database;
    try {
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM drive_logs'));
      return count ?? 0;
    } catch (e) {
      if (kDebugMode) {
        print('getTotalLogCount error: $e');
      }
      return 0;
    }
  }

  Future<Map<String, dynamic>> getTodayStats(String driveDateYmd) async {
    if (kIsWeb) {
      final logs = _mockLogsForWeb(driveDateYmd: driveDateYmd);
      int count = logs.length;
      int gross = logs.fold(0, (s, e) => s + (e['gross_fare'] as int));
      int net = logs.fold(0, (s, e) => s + (e['net_income'] as int));
      int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int));
      int extra_income = logs.fold(0, (s, e) => s + ((e['waypoint_tip'] as int?) ?? 0));
      return {'count': count, 'gross': gross, 'net': net, 'expenses': expenses, 'extra_income': extra_income};
    }
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count,
        COALESCE(SUM(gross_fare + COALESCE(waypoint_tip, 0)), 0) as gross,
        COALESCE(SUM(
          MAX(0,
            COALESCE(gross_fare, 0) + COALESCE(waypoint_tip, 0)
              - COALESCE(fee, 0) - COALESCE(transport_cost, 0) - COALESCE(insurance_fee, 0)
          )
        ), 0) as net,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0) + COALESCE(insurance_fee, 0)), 0) as expenses,
        COALESCE(SUM(COALESCE(waypoint_tip, 0)), 0) as extra_income
      FROM drive_logs WHERE drive_date = ?
      ''',
      [driveDateYmd],
    );
    return result.isNotEmpty ? result.first : {'count': 0, 'gross': 0, 'net': 0, 'expenses': 0};
  }

  /// 근무일(`work_date`) 기준. 총 매출(gross 키) = 요금+경유팁 합.
  Future<Map<String, dynamic>> getTodayStatsByWorkDate(String workDateYmd) async {
    if (kIsWeb) {
      final logs = _mockLogsForWeb(workDateYmd: workDateYmd);
      int count = logs.length;
      int gross = logs.fold(0, (s, e) => s + (e['gross_fare'] as int));
      int net = logs.fold(0, (s, e) => s + (e['net_income'] as int));
      int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int));
      int extra_income = logs.fold(0, (s, e) => s + ((e['waypoint_tip'] as int?) ?? 0));
      return {'count': count, 'gross': gross, 'net': net, 'expenses': expenses, 'extra_income': extra_income};
    }
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count,
        COALESCE(SUM(gross_fare + COALESCE(waypoint_tip, 0)), 0) as gross,
        COALESCE(SUM(
          MAX(0,
            COALESCE(gross_fare, 0) + COALESCE(waypoint_tip, 0)
              - COALESCE(fee, 0) - COALESCE(transport_cost, 0) - COALESCE(insurance_fee, 0)
          )
        ), 0) as net,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) as expenses,
        COALESCE(SUM(COALESCE(waypoint_tip, 0)), 0) as extra_income
      FROM drive_logs WHERE work_date = ?
      ''',
      [workDateYmd],
    );
    return result.isNotEmpty ? result.first : {'count': 0, 'gross': 0, 'net': 0, 'expenses': 0};
  }

  /// 운행일이 [startYmd] ~ [endYmd] (포함, `yyyy-MM-dd`) 인 일지.
  Future<List<Map<String, dynamic>>> getLogsByDriveDateRange(String startYmd, String endYmd) async {
    if (kIsWeb) return _mockLogsForWeb(startYmd: startYmd, endYmd: endYmd);
    final db = await database;
    return db.query(
      'drive_logs',
      where: 'drive_date >= ? AND drive_date <= ?',
      whereArgs: [startYmd, endYmd],
      orderBy: 'drive_date ASC, drive_time ASC',
    );
  }

  /// 근무일(`work_date`)이 [startYmd] ~ [endYmd] (포함). 구버전: work_date 비면 drive_date로 대체.
  Future<List<Map<String, dynamic>>> getLogsByWorkDateRange(String startYmd, String endYmd) async {
    if (kIsWeb) return _mockLogsForWeb(startYmd: startYmd, endYmd: endYmd);
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          '((work_date IS NOT NULL AND TRIM(work_date) != \'\' AND work_date >= ? AND work_date <= ?) '
          'OR ((work_date IS NULL OR TRIM(work_date) = \'\') AND drive_date >= ? AND drive_date <= ?))',
      whereArgs: [startYmd, endYmd, startYmd, endYmd],
      orderBy: 'work_date ASC, drive_date ASC, drive_time ASC',
    );
  }

  /// 단일 근무일(`yyyy-MM-dd`). 구버전: work_date 비면 drive_date 일치 행.
  Future<List<Map<String, dynamic>>> getLogsForWorkDate(String workDateYmd) async {
    if (kIsWeb) return _mockLogsForWeb(workDateYmd: workDateYmd);
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          '(work_date = ?) OR ((work_date IS NULL OR TRIM(work_date) = \'\') AND drive_date = ?)',
      whereArgs: [workDateYmd, workDateYmd],
      orderBy: 'drive_date ASC, drive_time ASC',
    );
  }

  /// 통계·집계용: **근무일(`work_date`)만** 일치 (비어 있으면 제외).
  Future<List<Map<String, dynamic>>> getLogsForWorkDateStrict(String workDateYmd) async {
    if (kIsWeb) return _mockLogsForWeb(workDateYmd: workDateYmd);
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          'work_date IS NOT NULL AND TRIM(work_date) != \'\' AND work_date = ?',
      whereArgs: [workDateYmd],
      orderBy: 'drive_date ASC, drive_time ASC',
    );
  }

  /// [getLogsForWorkDate]와 동일한 근무일 매칭으로, 그날 일지 중 **가장 늦은** `drive_time`(HH:mm) 하나.
  /// 일지가 없거나 파싱 가능한 시각이 없으면 null.
  Future<String?> getLatestDriveTimeHmOnWorkDate(String workDateYmd) async {
    final logs = await getLogsForWorkDate(workDateYmd);
    String? best;
    for (final log in logs) {
      final n = normalizeDriveTimeHm(log['drive_time']?.toString());
      if (n == null) continue;
      if (best == null || n.compareTo(best) > 0) best = n;
    }
    return best;
  }

  Future<List<Map<String, dynamic>>> getLogsByMonth(String yearMonth) async {
    if (kIsWeb) return _mockLogsForWeb(yearMonth: yearMonth);
    final db = await database;
    return db.query(
      'drive_logs',
      where: "drive_date LIKE ?",
      whereArgs: ['$yearMonth-%'],
      orderBy: 'drive_date DESC, drive_time DESC'
    );
  }

  /// 근무일(`work_date`) 기준 월 목록. (구버전 데이터 호환: work_date 비어있으면 drive_date 사용)
  Future<List<Map<String, dynamic>>> getLogsByWorkMonth(String yearMonth) async {
    if (kIsWeb) return _mockLogsForWeb(yearMonth: yearMonth);
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          "(work_date LIKE ?) OR ((work_date IS NULL OR TRIM(work_date) = '') AND drive_date LIKE ?)",
      whereArgs: ['$yearMonth-%', '$yearMonth-%'],
      orderBy: 'work_date DESC, drive_date DESC, drive_time DESC',
    );
  }

  /// 통계용 주간·월간 합산: **근무일(`work_date`)만** 사용 (비어 있으면 제외).
  /// 일자별 차트·상단 합계와 동일 기준을 맞춘다.
  Future<List<Map<String, dynamic>>> getLogsByWorkDateRangeStrict(String startYmd, String endYmd) async {
    if (kIsWeb) return _mockLogsForWeb(startYmd: startYmd, endYmd: endYmd);
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          'work_date IS NOT NULL AND TRIM(work_date) != \'\' '
          'AND work_date >= ? AND work_date <= ?',
      whereArgs: [startYmd, endYmd],
      orderBy: 'work_date ASC, drive_date ASC, drive_time ASC',
    );
  }

  /// 통계용 월 목록: **근무일(`work_date`)만** (비어 있으면 제외).
  Future<List<Map<String, dynamic>>> getLogsByWorkMonthStrict(String yearMonth) async {
    if (kIsWeb) return _mockLogsForWeb(yearMonth: yearMonth);
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          'work_date IS NOT NULL AND TRIM(work_date) != \'\' AND work_date LIKE ?',
      whereArgs: ['$yearMonth-%'],
      orderBy: 'work_date ASC, drive_date ASC, drive_time ASC',
    );
  }

  Future<int> deleteLog(int id) async {
    final db = await database;
    final n = await db.delete('drive_logs', where: 'id = ?', whereArgs: [id]);
    await db.delete('call_points', where: 'log_id = ? AND type = ?', whereArgs: [id, 'log']);
    afterLogsChanged?.call();
    return n;
  }

  // ── Local Notices (공지사항 푸시) ──────────────────────────────────
  Future<int> insertNotice(String title, String body) async {
    if (kIsWeb) return 0;
    final db = await database;
    final Map<String, dynamic> data = {
      'title': title,
      'body': body,
      'received_at': DateTime.now().toIso8601String(),
      'is_read': 0,
    };
    return await db.insert('local_notices', data);
  }

  Future<int> getUnreadNoticeCount() async {
    if (kIsWeb) return 0;
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM local_notices WHERE is_read = 0');
    if (result.isNotEmpty) {
      return Sqflite.firstIntValue(result) ?? 0;
    }
    return 0;
  }

  Future<int> markNoticeAsRead(int id) async {
    if (kIsWeb) return 0;
    final db = await database;
    return await db.update(
      'local_notices',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getNotices() async {
    if (kIsWeb) return [];
    final db = await database;
    return await db.query(
      'local_notices',
      orderBy: 'id DESC',
    );
  }

  Future<int> deleteAllNotices() async {
    if (kIsWeb) return 0;
    final db = await database;
    return await db.delete('local_notices');
  }

  // ── Work Sessions (근무 시간) ──────────────────────────────────
  Future<Map<String, dynamic>?> getWorkSessionForWorkDate(String ymd) async {
    if (kIsWeb) return null;
    final db = await database;
    final r = await db.query(
      'daily_work_sessions',
      where: 'work_date = ?',
      whereArgs: [ymd],
      limit: 1,
    );
    return r.isNotEmpty ? r.first : null;
  }

  Future<int> getTotalWorkSecondsForWorkDateRange(String startYmd, String endYmd) async {
    if (kIsWeb) return 0;
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_seconds), 0) as s FROM daily_work_sessions WHERE work_date >= ? AND work_date <= ?',
      [startYmd, endYmd],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  Future<int> getTotalWorkSecondsForWorkMonth(String yearMonth) async {
    if (kIsWeb) return 0;
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_seconds), 0) as s FROM daily_work_sessions WHERE work_date LIKE ?',
      ['$yearMonth-%'],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }
}
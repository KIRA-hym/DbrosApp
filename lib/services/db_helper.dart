import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../utils/drive_time_format.dart';
import '../utils/work_date_utils.dart';

class DriveLogDatabase {
  DriveLogDatabase._();
  static final DriveLogDatabase instance = DriveLogDatabase._();
  Database? _db;

  /// 일지 저장·삭제 후 호출 (고정 알림 갱신 등).
  static void Function()? afterLogsChanged;

  static List<Map<String, dynamic>> _mockLogsAllForWeb() {
    final ymd = WorkDateUtils.effectiveWorkDateYmd();
    return [
      {
        'id': 1, 'work_date': ymd, 'drive_date': ymd, 'drive_time': '21:30',
        'program': '카카오(일반)', 'gross_fare': 30000, 'fee': 6000, 'transport_cost': 0, 'waypoint_tip': 0, 'net_income': 24000,
        'start_location': '서울 강남구 역삼동', 'waypoint': '', 'end_location': '경기 성남시 분당구',
      },
      {
        'id': 2, 'work_date': ymd, 'drive_date': ymd, 'drive_time': '22:45',
        'program': '로지', 'gross_fare': 45000, 'fee': 9000, 'transport_cost': 3000, 'waypoint_tip': 0, 'net_income': 33000,
        'start_location': '경기 성남시 분당구', 'waypoint': '', 'end_location': '서울 마포구 합정동',
      },
      {
        'id': 3, 'work_date': ymd, 'drive_date': ymd, 'drive_time': '00:15',
        'program': '콜마너', 'gross_fare': 25000, 'fee': 5000, 'transport_cost': 0, 'waypoint_tip': 0, 'net_income': 20000,
        'start_location': '서울 마포구 합정동', 'waypoint': '서대문구 창천동', 'end_location': '경기 고양시 일산동구',
      },
    ];
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
      version: 7,
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
            updated_at TEXT
          )
        ''');
        await _ensureDriveLogsSchema(db);
        await _ensureExpenseTables(db);
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
      },
      onOpen: (db) async {
        // 일부 기존 설치본은 버전/스키마가 불일치할 수 있어 실행 시점에 자체 복구.
        await _ensureDriveLogsSchema(db);
        await _ensureExpenseTables(db);
      },
    );
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
    final int result;
    if (out.containsKey('id') && out['id'] != null) {
      result = await db.update('drive_logs', out, where: 'id = ?', whereArgs: [out['id']]);
    } else {
      result = await db.insert("drive_logs", out, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    afterLogsChanged?.call();
    return result;
  }

  Future<List<Map<String, dynamic>>> getRecentLogs({int limit = 10}) async {
    if (kIsWeb) return _mockLogsAllForWeb().reversed.take(limit).toList();
    final db = await database;
    return db.query('drive_logs', orderBy: 'work_date DESC, drive_date DESC, drive_time DESC', limit: limit);
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
  Future<Map<String, dynamic>> getTodayStats(String driveDateYmd) async {
    if (kIsWeb) {
      final logs = _mockLogsForWeb(driveDateYmd: driveDateYmd);
      int count = logs.length;
      int gross = logs.fold(0, (s, e) => s + (e['gross_fare'] as int));
      int net = logs.fold(0, (s, e) => s + (e['net_income'] as int));
      int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int));
      return {'count': count, 'gross': gross, 'net': net, 'expenses': expenses};
    }
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count,
        COALESCE(SUM(gross_fare + COALESCE(waypoint_tip, 0)), 0) as gross,
        COALESCE(SUM(
          MAX(0,
            COALESCE(gross_fare, 0) + COALESCE(waypoint_tip, 0)
              - COALESCE(fee, 0) - COALESCE(transport_cost, 0)
          )
        ), 0) as net,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) as expenses
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
      return {'count': count, 'gross': gross, 'net': net, 'expenses': expenses};
    }
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count,
        COALESCE(SUM(gross_fare + COALESCE(waypoint_tip, 0)), 0) as gross,
        COALESCE(SUM(
          MAX(0,
            COALESCE(gross_fare, 0) + COALESCE(waypoint_tip, 0)
              - COALESCE(fee, 0) - COALESCE(transport_cost, 0)
          )
        ), 0) as net,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) as expenses
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
    afterLogsChanged?.call();
    return n;
  }
}
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DriveLogDatabase {
  DriveLogDatabase._();
  static final DriveLogDatabase instance = DriveLogDatabase._();
  Database? _db;

  /// 일지 저장·삭제 후 호출 (고정 알림 갱신 등).
  static void Function()? afterLogsChanged;

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
      version: 4,
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
      },
    );
  }

  Future<int> insertOrUpdateDriveLog(Map<String, dynamic> row) async {
    final db = await database;
    final int result;
    if (row.containsKey('id') && row['id'] != null) {
      result = await db.update('drive_logs', row, where: 'id = ?', whereArgs: [row['id']]);
    } else {
      result = await db.insert("drive_logs", row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    afterLogsChanged?.call();
    return result;
  }

  Future<List<Map<String, dynamic>>> getRecentLogs({int limit = 10}) async {
    final db = await database;
    return db.query('drive_logs', orderBy: 'work_date DESC, drive_date DESC, drive_time DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getRecentLogsByDriveDateTime({int limit = 10}) async {
    final db = await database;
    return db.query('drive_logs', orderBy: 'drive_date DESC, drive_time DESC', limit: limit);
  }

  /// 운행일(`drive_date`) 기준: 수입 = gross + waypoint_tip, 지출 = fee + transport
  Future<Map<String, int>> getTodayIncomeExpense(String driveDateYmd) async {
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

  /// 운행일(`drive_date`) 기준. 총 매출(gross 키) = 요금+경유팁 합.
  Future<Map<String, dynamic>> getTodayStats(String driveDateYmd) async {
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
    final db = await database;
    return db.query(
      'drive_logs',
      where: 'drive_date >= ? AND drive_date <= ?',
      whereArgs: [startYmd, endYmd],
      orderBy: 'drive_date ASC, drive_time ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getLogsByMonth(String yearMonth) async {
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
    final db = await database;
    return db.query(
      'drive_logs',
      where:
          "(work_date LIKE ?) OR ((work_date IS NULL OR TRIM(work_date) = '') AND drive_date LIKE ?)",
      whereArgs: ['$yearMonth-%', '$yearMonth-%'],
      orderBy: 'work_date DESC, drive_date DESC, drive_time DESC',
    );
  }

  Future<int> deleteLog(int id) async {
    final db = await database;
    final n = await db.delete('drive_logs', where: 'id = ?', whereArgs: [id]);
    afterLogsChanged?.call();
    return n;
  }
}
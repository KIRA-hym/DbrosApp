import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
    final ymd = WorkDateUtils.effectiveWorkDateYmd();
    return [
      {
        'id': 1, 'work_date': ymd, 'drive_date': ymd, 'drive_time': '21:30',
        'program': '카카오(일반)', 'gross_fare': 30000, 'fee': 6000, 'transport_cost': 0, 'waypoint_tip': 0, 'net_income': 24000,
        'start_location': '서울 강남구 역삼동', 'waypoint': '', 'end_location': '경기 성남시 분당구',
        'start_lat': 37.5006, 'start_lng': 127.0364, 'end_lat': 37.3827, 'end_lng': 127.1189,
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
      version: 11,
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
            income_category TEXT
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
      },
      onOpen: (db) async {
        // 일부 기존 설치본은 버전/스키마가 불일치할 수 있어 실행 시점에 자체 복구.
        await _ensureDriveLogsSchema(db);
        await _ensureExpenseTables(db);
        await _ensureCallPointsTable(db);
        await _ensureLocalNoticesTable(db);
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
        log_id INTEGER
      )
    ''');
    // Ensure log_id column exists
    final List<Map<String, Object?>> rows = await db.rawQuery("PRAGMA table_info(call_points)");
    if (rows.isNotEmpty) {
      final columns = rows.map((r) => r['name'].toString()).toSet();
      if (!columns.contains('log_id')) {
        await db.execute('ALTER TABLE call_points ADD COLUMN log_id INTEGER');
      }
    }
    
    // Seed reference data if none exists
    final refCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM call_points WHERE type = 'reference'")) ?? 0;
    if (refCount == 0) {
      final references = [
        ['오목교역 (현대백화점/41타워/CBS 앞)', 37.525565, 126.872851],
        ['목동역 (목동 로데오거리 메인)', 37.528047, 126.861496],
        ['여의도 샛강역 (KBS별관 뒷골목 식당가)', 37.519381, 126.931641],
        ['논현동 (영동시장/백종원거리)', 37.507851, 127.023812],
        ['역삼동 (테헤란로 이면 르네상스호텔 뒤)', 37.502800, 127.039600],
        ['신사동 (가로수길/압구정 로데오)', 37.523450, 127.022500],
        ['대치동 (선릉역 1번출구 먹자골목)', 37.503463, 127.050689],
        ['교대역 (서초대로 이면도로)', 37.493500, 127.014000],
        ['당산역 (지하철 2/9호선 아래 먹자골목)', 37.534500, 126.902500],
        ['영등포역 (타임스퀘어 상권)', 37.515413, 126.907128],
        ['가락동 (경찰병원역/가락시장 먹자)', 37.496500, 127.120500],
        ['방이동 (방이먹자골목 메인사거리)', 37.514415, 127.109015],
        ['잠실새내역 (구 신천역 성당 앞)', 37.510616, 127.081827],
        ['천호동 (천호 로데오거리)', 37.539318, 127.127028],
        ['사당동 (사당역 파스텔시티 뒤편)', 37.476483, 126.982542],
        ['신림동 (순대타운/걷고싶은거리)', 37.483980, 126.929875],
        ['봉천동 (서울대입구역 샤로수길)', 37.479590, 126.953880],
        ['구로동 (구디역 깔깔거리)', 37.485200, 126.901500],
        ['가산동 (현대아울렛/마리오 사거리)', 37.477500, 126.888500],
        ['독산동 (맛나거리/우시장 인근)', 37.468500, 126.897500],
        ['마곡동 (마곡동로 먹자골목)', 37.558500, 126.837000],
        ['화곡동 (까치산역 복개천 상권)', 37.531500, 126.846500],
        ['서교동 (홍대 클럽거리/상상마당)', 37.550875, 126.920800],
        ['연남동 (경의선 숲길/동진시장)', 37.562300, 126.925000],
        ['신촌동 (연세로/명물거리)', 37.558356, 126.936630],
        ['이태원동 (세계음식거리/해방촌입구)', 37.534500, 126.993500],
        ['종로 (종각 젊음의거리)', 37.568997, 126.985670],
        ['을지로 (을지로3가 노가리골목)', 37.566500, 126.992500],
        ['자양동 (건대입구 맛의거리)', 37.540372, 127.069276],
        ['왕십리동 (한양대 먹자골목)', 37.561500, 127.037500],
        ['장안동 (장한평 먹자골목/안마상권)', 37.561500, 127.064500],
        ['동선동 (성신여대 로데오거리)', 37.592500, 127.016500],
        ['수유동 (강북구청 상권)', 37.638200, 127.025500],
        ['노원동 (노원역 문화의거리)', 37.654500, 127.060500],
        ['창동 (창동역 포장마차거리)', 37.653000, 127.047500],
        ['대조동 (연신내 로데오거리)', 37.618600, 126.920500],
        ['상봉동 (상봉터미널 먹자골목)', 37.596500, 127.085500],
        ['동춘동 (라마다송도호텔/구송도 먹자골목)', 37.414166, 126.655366],
        ['삼산동 (굴포천역 롯데마트 뒤 먹자골목)', 37.508231, 126.735784],
        ['부평동 (테마의거리/문화의거리)', 37.493500, 126.723500],
        ['구월동 (로데오거리/예술회관역)', 37.444882, 126.700584],
        ['간석동 (올리브백화점/간석오거리 상권)', 37.464500, 126.708500],
        ['논현동 (호구포역/소래포구 어시장)', 37.398500, 126.732500],
        ['청학동 (시대아파트 앞/연수역 상권)', 37.418500, 126.668500],
        ['연수동 (힘찬병원 뒤 먹자골목)', 37.418500, 126.678500],
        ['송도동 (트리플스트리트/해양경찰청)', 37.381500, 126.658500],
        ['계산동 (계양구청/아라비안나이트 인근)', 37.537500, 126.737500],
        ['주안동 (2030거리/먹자골목)', 37.456500, 126.680500],
        ['청라동 (커낼웨이 수변상가)', 37.530500, 126.653500],
        ['검단동 (검단사거리 먹자골목)', 37.601500, 126.650500],
        ['신포동 (동인천역/신포국제시장)', 37.471500, 126.631500],
        ['중동 (신중동 시계탑 먹자골목)', 37.503450, 126.772580],
        ['상동 (세이브존 뒤/나이트 상권)', 37.505814, 126.753163],
        ['상동 (송내역 북부 둘리광장)', 37.488210, 126.750230],
        ['고강동 (고강제일시장/국민은행 부근)', 37.528314, 126.814653],
        ['역곡동 (역곡 북부 상상시장/대학가)', 37.486750, 126.806540],
        ['심곡동 (부천역 북부 피노키오상가 일대)', 37.484520, 126.782850],
        ['소사본동 (소사삼거리/부천대 부속병원 앞)', 37.480500, 126.795500],
        ['까치울 (장어/백숙 외곽 가든촌)', 37.509500, 126.812500],
        ['정왕동 (시화 48블럭/51블럭 유흥가)', 37.346310, 126.732655],
        ['배곧동 (배곧신도시 중심상가)', 37.368500, 126.728900],
        ['하안동 (하안사거리 상업지구 공영주차장)', 37.462528, 126.881339],
        ['철산동 (철산상업지구 로데오 메인)', 37.476500, 126.868500],
        ['고잔동 (안산 중앙역 로데오/NC 뒤)', 37.308562, 126.851517],
        ['선부동 (동명상가 사거리)', 37.332500, 126.812500],
        ['이동 (한대앞역 로데오거리)', 37.310500, 126.855000],
        ['평촌동 (범계역 로데오/평촌학원가)', 37.389500, 126.950400],
        ['안양동 (안양일번가 메인)', 37.401120, 126.922000],
        ['산본동 (산본역 중심상가)', 37.361500, 126.935500],
        ['내손동 (계원예대 앞 먹자골목)', 37.384500, 126.974500],
        ['인계동 (나혜석거리/수원시청 뒤 박스)', 37.264229, 127.033279],
        ['영통동 (영통 중심상가/시계탑)', 37.251410, 127.076890],
        ['매탄동 (삼성전자 영통구청 앞)', 37.261500, 127.045600],
        ['호매실동 (호매실지구 중심상가)', 37.268500, 126.960500],
        ['서현동 (서현역 로데오거리)', 37.385973, 127.124746],
        ['정자동 (정자 카페거리/엠코헤리츠)', 37.368500, 127.106500],
        ['삼평동 (판교 유스페이스/H스퀘어)', 37.400500, 127.104200],
        ['성남동 (모란역 먹자골목)', 37.432422, 127.131559],
        ['반송동 (동탄 남광장/북광장)', 37.205775, 127.073275],
        ['영천동 (동탄2신도시 11자 상가)', 37.206500, 127.114500],
        ['진안동 (병점 중심상가)', 37.207800, 127.039200],
        ['향남읍 (향남지구 로데오)', 37.130500, 126.920500],
        ['마도면 (마도공단 외국인상가)', 37.213500, 126.762500],
        ['비전동 (평택 소사벌 상업지구)', 37.000166, 127.113989],
        ['평택동 (평택역 먹자골목)', 36.992500, 127.087200],
        ['포승읍 (평택항/포승공단)', 36.960500, 126.840500],
        ['공도읍 (안성 공도터미널 먹자)', 36.998500, 127.168500],
        ['장항동 (라페스타/웨스턴돔)', 37.660709, 126.768958],
        ['백석동 (백석역 8블럭 먹자골목)', 37.643200, 126.786500],
        ['화정동 (화정역 문화의거리/로데오)', 37.634500, 126.832500],
        ['사우동 (김포시청 앞 먹자골목)', 37.620500, 126.718500],
        ['장기동 (장기역 먹자골목/수변상가)', 37.644500, 126.668500],
        ['구래동 (구래 중심상업지구)', 37.645000, 126.628000],
        ['야당동 (야당역 먹자골목)', 37.712500, 126.761500],
        ['의정부동 (신시가지/로데오)', 37.738000, 127.045000],
        ['옥정동 (양주 옥정신도시 중심상가)', 37.820500, 127.094500],
        ['수택동 (구리 돌다리/먹자골목)', 37.599500, 127.138500],
        ['별내동 (별내 로데오/카페거리)', 37.641500, 127.125500],
        ['진접읍 (진접지구 로데오)', 37.718500, 127.175500],
        ['화도읍 (마석역/마석우리 먹자골목)', 37.652500, 127.306500],
        ['망월동 (하남 미사역 문화의거리)', 37.568500, 127.189500],
        ['경안동 (광주시내 상권)', 37.412500, 127.256500],
        ['용두동 (서오릉 장어/갈비촌)', 37.625891, 126.891931],
        ['광탄면 (서원밸리CC/벽초지 인근)', 37.764395, 126.903643],
        ['이동면 (일동레이크 이동갈비촌)', 38.034007, 127.366106],
        ['고매동 (기흥IC/코리아CC 인근)', 37.221106, 127.103789],
        ['양지면 (양지IC/아시아나CC 인근)', 37.231694, 127.286713],
        ['마장면 (덕평IC 한우/쌀밥촌)', 37.225583, 127.370524],
        ['창전동 (이천 하이닉스/시내 상권)', 37.279500, 127.442500],
        ['가남읍 (솔모로/자유CC 인근)', 37.206336, 127.541363],
        ['도척면 (곤지암 소머리국밥거리)', 37.350605, 127.335824],
        ['퇴촌면 (앵자봉 계곡 식당가)', 37.465200, 127.316800],
        ['양성면 (안성베네스트 고기거리)', 37.067500, 127.235100],
        ['두정동 (먹자골목 중심부)', 36.833610, 127.135482],
        ['불당동 (신불당 상업지구)', 36.814500, 127.104200],
        ['쌍용동 (나사렛대/열린치과 앞)', 36.797500, 127.126500],
        ['신방동 (신방먹자골목)', 36.786500, 127.128500],
        ['성환읍 (성환역/터미널 상권)', 36.916500, 127.127500],
        ['용화동 (신용화동 먹자골목)', 36.772158, 126.995530],
        ['탕정면 (지중해마을/트라팰리스)', 36.799000, 127.065000],
        ['배방읍 (공수리 상권)', 36.775000, 127.054000],
        ['둔포면 (아산테크노밸리 상가)', 36.925500, 127.037500],
        ['예천동 (호수공원 상권)', 36.775538, 126.449848],
        ['동문동 (서산 동문동 먹자골목)', 36.782000, 126.455000],
        ['대산읍 (대산공단 명지사거리)', 36.953500, 126.381500],
        ['읍내동 (당진 우두동 먹자골목)', 36.886707, 126.635066],
        ['송악읍 (기지시리 로터리)', 36.903500, 126.685500],
        ['홍북읍 (내포신도시 중심상가)', 36.602500, 126.678000]
      ];
      final batch = db.batch();
      for (var r in references) {
        batch.insert('call_points', {
          'type': 'reference',
          'is_mine': 0,
          'start_location': r[0],
          'start_lat': r[1],
          'start_lng': r[2],
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
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
              - COALESCE(fee, 0) - COALESCE(transport_cost, 0)
          )
        ), 0) as net,
        COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) as expenses,
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
              - COALESCE(fee, 0) - COALESCE(transport_cost, 0)
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
}
import 'package:sqflite/sqflite.dart';

import 'db_helper.dart';

typedef ExpenseChangedCallback = void Function();

class ExpenseRepository {
  ExpenseRepository._();

  static ExpenseChangedCallback? afterExpensesChanged;

  static void _notify() => afterExpensesChanged?.call();

  static Future<Database> get _db async => DriveLogDatabase.instance.database;

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await _db;
    return db.query('expense_categories', orderBy: 'sort_order ASC, id ASC');
  }

  static Future<List<String>> getCategoryNames() async {
    final rows = await getCategories();
    return rows.map((r) => (r['name'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
  }

  static Future<int?> findCategoryIdByName(String name) async {
    final db = await _db;
    final rows = await db.query(
      'expense_categories',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num?)?.toInt();
  }

  static Future<void> addCategory(String name) async {
    final t = name.trim();
    if (t.isEmpty) return;
    final db = await _db;
    final maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM expense_categories',
    );
    final ord = (maxRow.first['n'] as num?)?.toInt() ?? 0;
    await db.insert('expense_categories', {'name': t, 'sort_order': ord});
    _notify();
  }

  static Future<void> deleteCategory(int id) async {
    final db = await _db;
    await db.delete('expense_categories', where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  static Future<List<Map<String, dynamic>>> getEntriesByExpenseMonth(String yearMonth) async {
    final db = await _db;
    return db.query(
      'expense_entries',
      where: 'expense_date LIKE ?',
      whereArgs: ['$yearMonth-%'],
      orderBy: 'expense_date DESC, written_at DESC',
    );
  }

  static Future<List<Map<String, dynamic>>> getEntriesForExpenseDate(String ymd) async {
    final db = await _db;
    return db.query(
      'expense_entries',
      where: 'expense_date = ?',
      whereArgs: [ymd],
      orderBy: 'written_at ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getEntriesByExpenseDateRange(
    String startYmd,
    String endYmd,
  ) async {
    final db = await _db;
    return db.query(
      'expense_entries',
      where: 'expense_date >= ? AND expense_date <= ?',
      whereArgs: [startYmd, endYmd],
      orderBy: 'expense_date ASC, written_at ASC',
    );
  }

  static Future<int> sumAmountForExpenseMonth(String yearMonth) async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM expense_entries WHERE expense_date LIKE ?',
      ['$yearMonth-%'],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  static Future<int> sumAmountForExpenseDate(String ymd) async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM expense_entries WHERE expense_date = ?',
      [ymd],
    );
    return (r.first['s'] as num?)?.toInt() ?? 0;
  }

  static Future<int> countForExpenseDate(String ymd) async {
    final db = await _db;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM expense_entries WHERE expense_date = ?',
      [ymd],
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 월별: 지출이 있는 항목만 (amount > 0).
  static Future<List<Map<String, dynamic>>> aggregateByCategoryForMonthNonEmpty(String yearMonth) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT category_name AS label, SUM(amount) AS amount, COUNT(*) AS cnt
      FROM expense_entries
      WHERE expense_date LIKE ?
      GROUP BY category_name
      HAVING SUM(amount) > 0
      ORDER BY amount DESC
      ''',
      ['$yearMonth-%'],
    );
    return rows
        .map(
          (e) => <String, dynamic>{
            'label': e['label']?.toString() ?? '',
            'amount': (e['amount'] as num?)?.toInt() ?? 0,
            'count': (e['cnt'] as num?)?.toInt() ?? 0,
          },
        )
        .toList();
  }

  /// 기간 내 항목별 합계. [includeAllDefinedCategories]이면 설정 항목 중 데이터 없는 것은 0으로 포함.
  static Future<List<Map<String, dynamic>>> aggregateByCategoryForRange(
    String startYmd,
    String endYmd, {
    required bool includeAllDefinedCategories,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT category_name AS label, SUM(amount) AS amount, COUNT(*) AS cnt
      FROM expense_entries
      WHERE expense_date >= ? AND expense_date <= ?
      GROUP BY category_name
      ''',
      [startYmd, endYmd],
    );
    final map = <String, int>{};
    final countMap = <String, int>{};
    for (final e in rows) {
      final label = e['label']?.toString() ?? '';
      map[label] = (e['amount'] as num?)?.toInt() ?? 0;
      countMap[label] = (e['cnt'] as num?)?.toInt() ?? 0;
    }
    if (includeAllDefinedCategories) {
      final cats = await getCategoryNames();
      for (final n in cats) {
        map.putIfAbsent(n, () => 0);
        countMap.putIfAbsent(n, () => 0);
      }
    }
    final labels = map.keys.toList()..sort();
    return labels
        .map(
          (label) => <String, dynamic>{
            'label': label,
            'amount': map[label] ?? 0,
            'count': countMap[label] ?? 0,
          },
        )
        .toList();
  }

  static Future<List<Map<String, dynamic>>> aggregateByDayForMonth(String yearMonth) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT expense_date AS ymd, SUM(amount) AS amount, COUNT(*) AS cnt
      FROM expense_entries
      WHERE expense_date LIKE ?
      GROUP BY expense_date
      ORDER BY expense_date ASC
      ''',
      ['$yearMonth-%'],
    );
    return rows
        .map(
          (e) => <String, dynamic>{
            'ymd': e['ymd']?.toString() ?? '',
            'dayLabel': '${(e['ymd']?.toString() ?? '').split('-').last}일',
            'amount': (e['amount'] as num?)?.toInt() ?? 0,
            'count': (e['cnt'] as num?)?.toInt() ?? 0,
          },
        )
        .toList();
  }

  /// 홈 일자별 차트용: 해당 월 1일~말일 x축 고정, 지출 없는 일은 0.
  static Future<List<Map<String, dynamic>>> allDaysInMonthForChart(String yearMonth) async {
    final parts = yearMonth.split('-');
    if (parts.length < 2) return [];
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    if (y < 2000 || m < 1 || m > 12) return [];
    final lastDay = DateTime(y, m + 1, 0).day;
    final agg = await aggregateByDayForMonth(yearMonth);
    final byYmd = <String, int>{};
    for (final e in agg) {
      final key = e['ymd']?.toString() ?? '';
      if (key.isNotEmpty) {
        byYmd[key] = (e['amount'] as num?)?.toInt() ?? 0;
      }
    }
    final out = <Map<String, dynamic>>[];
    for (var d = 1; d <= lastDay; d++) {
      final ymd =
          '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      out.add(<String, dynamic>{
        'label': '$d일',
        'amount': byYmd[ymd] ?? 0,
      });
    }
    return out;
  }

  static Future<int> insertEntry({
    required String expenseDateYmd,
    required String writtenAtIso,
    int? categoryId,
    required String categoryName,
    required int amount,
    String memo = '',
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('expense_entries', {
      'expense_date': expenseDateYmd,
      'written_at': writtenAtIso,
      'category_id': categoryId,
      'category_name': categoryName,
      'amount': amount,
      'memo': memo,
      'created_at': now,
      'updated_at': now,
    });
    _notify();
    return id;
  }

  static Future<void> updateEntry(int id, Map<String, dynamic> row) async {
    final db = await _db;
    final copy = Map<String, dynamic>.from(row);
    copy['updated_at'] = DateTime.now().toIso8601String();
    await db.update('expense_entries', copy, where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  static Future<void> deleteEntry(int id) async {
    final db = await _db;
    await db.delete('expense_entries', where: 'id = ?', whereArgs: [id]);
    _notify();
  }

  static Future<List<Map<String, dynamic>>> exportCategoriesForBackup() async {
    final db = await _db;
    return db.query('expense_categories', orderBy: 'sort_order ASC, id ASC');
  }

  static Future<List<Map<String, dynamic>>> exportEntriesForBackup() async {
    final db = await _db;
    return db.query('expense_entries', orderBy: 'id ASC');
  }

  static Future<void> replaceFromBackup({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> entries,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('expense_entries');
      await txn.delete('expense_categories');
      for (final c in categories) {
        await txn.insert('expense_categories', Map<String, dynamic>.from(c));
      }
      for (final e in entries) {
        await txn.insert('expense_entries', Map<String, dynamic>.from(e));
      }
    });
    _notify();
  }
}

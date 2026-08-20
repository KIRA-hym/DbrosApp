import 'dart:io';

void main() {
  final file = File('lib/services/db_helper.dart');
  String code = file.readAsStringSync();

  // 1. Fix getTodayIncomeExpenseByWorkDate (mock)
  code = code.replaceFirst(
    "'expense': logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int)),",
    "'expense': logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int) + ((e['insurance_fee'] as int?) ?? 0)),",
  );

  // 2. Fix getTodayIncomeExpenseByWorkDate (SQL)
  code = code.replaceFirst(
    "COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) AS expense",
    "COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0) + COALESCE(insurance_fee, 0)), 0) AS expense",
  );

  // 3. Fix getTodayStats (mock)
  code = code.replaceFirst(
    "int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int));",
    "int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int) + ((e['insurance_fee'] as int?) ?? 0));",
  );

  // 4. Fix getTodayStatsByWorkDate (mock)
  // This will replace the remaining instance(s) since we just replaced the first one.
  code = code.replaceFirst(
    "int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int));",
    "int expenses = logs.fold(0, (s, e) => s + (e['fee'] as int) + (e['transport_cost'] as int) + ((e['insurance_fee'] as int?) ?? 0));",
  );

  // 5. Fix getTodayStatsByWorkDate (SQL)
  code = code.replaceFirst(
    "COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0)), 0) as expenses,",
    "COALESCE(SUM(COALESCE(fee, 0) + COALESCE(transport_cost, 0) + COALESCE(insurance_fee, 0)), 0) as expenses,",
  );

  file.writeAsStringSync(code);
  print("db_helper.dart expenses fixed.");
}

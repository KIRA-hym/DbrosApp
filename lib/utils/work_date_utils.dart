import 'package:intl/intl.dart';

import 'drive_time_format.dart';

/// 근무일자(work_date)와 운행일자(drive_date) 보조.
class WorkDateUtils {
  WorkDateUtils._();

  /// 근무일이 바뀌는 시각(로컬). 이 시각 **이전**에는 전날 근무일, **이후**부터 당일 근무일.
  static const int workDayRolloverHour = 9;

  /// 매일 [workDayRolloverHour]시 이전에는 **전날** `yyyy-MM-dd`, 이후에는 **달력 기준 당일**.
  static String effectiveWorkDateYmd([DateTime? now]) {
    final n = now ?? DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    if (n.hour < workDayRolloverHour) {
      return DateFormat('yyyy-MM-dd').format(d.subtract(const Duration(days: 1)));
    }
    return DateFormat('yyyy-MM-dd').format(d);
  }

  /// [effectiveWorkDateYmd]에 해당하는 날짜의 자정(로컬).
  static DateTime effectiveWorkDateStartOfDay([DateTime? now]) {
    return DateFormat('yyyy-MM-dd').parseStrict(effectiveWorkDateYmd(now));
  }

  static String addDays(String yyyyMmDd, int days) {
    final d = DateFormat('yyyy-MM-dd').parseStrict(yyyyMmDd);
    return DateFormat('yyyy-MM-dd').format(d.add(Duration(days: days)));
  }

  /// 새벽 00~01시는 익일 운행으로 간주 → **운행일자**를 근무일자 다음 날로 (콜카드 자동 등록 등).
  static String resolveDriveDateForNightShift(String workDateYmd, String driveTimeHm) {
    final nt = normalizeDriveTimeHm(driveTimeHm) ?? driveTimeHm.trim();
    final parts = nt.split(':');
    if (parts.isEmpty) return workDateYmd;
    final h = int.tryParse(parts[0]) ?? 12;
    if (h <= 1) return addDays(workDateYmd, 1);
    return workDateYmd;
  }

  static int hourFromHm(String hm) {
    final nt = normalizeDriveTimeHm(hm) ?? hm.trim();
    final parts = nt.split(':');
    return int.tryParse(parts.isNotEmpty ? parts[0] : '12') ?? 12;
  }
}

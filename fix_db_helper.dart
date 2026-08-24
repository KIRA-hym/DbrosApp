import 'dart:io';

void main() {
  final file = File('lib/services/db_helper.dart');
  String content = file.readAsStringSync();

  final oldFunc = r"""Future<String?> getLatestDriveTimeHmOnWorkDate(String workDateYmd) async {
    final logs = await getLogsForWorkDate(workDateYmd);
    String? best;
    for (final log in logs) {
      final n = normalizeDriveTimeHm(log['drive_time']?.toString());
      if (n == null) continue;
      if (best == null || n.compareTo(best) > 0) best = n;
    }
    return best;
  }""";

  final newFunc = """Future<String?> getLatestDriveTimeHmOnWorkDate(String workDateYmd) async {
    final logs = await getLogsForWorkDate(workDateYmd);
    String? best;
    DateTime? bestDt;
    for (final log in logs) {
      final n = normalizeDriveTimeHm(log['drive_time']?.toString());
      if (n == null) continue;
      
      final driveDateStr = WorkDateUtils.resolveDriveDateForNightShift(workDateYmd, n);
      final currentDt = DateTime.tryParse('\$driveDateStr \$n:00');
      
      if (currentDt == null) continue;
      
      if (bestDt == null || currentDt.isAfter(bestDt)) {
        bestDt = currentDt;
        best = n;
      }
    }
    return best;
  }""";

  if (content.contains(oldFunc)) {
      content = content.replaceFirst(oldFunc, newFunc);
      file.writeAsStringSync(content);
      print('Fixed getLatestDriveTimeHmOnWorkDate');
  } else {
      print('Could not find exact function match. Trying regex.');
      final funcRegex = RegExp(r'Future<String\?> getLatestDriveTimeHmOnWorkDate\(String workDateYmd\) async \{.*?return best;\s*\}', dotAll: true);
      if (funcRegex.hasMatch(content)) {
          content = content.replaceFirst(funcRegex, newFunc);
          file.writeAsStringSync(content);
          print('Fixed getLatestDriveTimeHmOnWorkDate with regex');
      } else {
          print('Failed to find getLatestDriveTimeHmOnWorkDate completely.');
      }
  }
}

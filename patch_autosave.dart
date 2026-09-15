import 'dart:io';

void main() {
  final f = File('lib/services/call_card_ocr_parse_service.dart');
  var text = f.readAsStringSync();
  
  final target = '''    final dateToUse = originalDate ?? DateTime.now();
    final work = WorkDateUtils.effectiveWorkDateYmd(dateToUse);
    final timeStr = formatDriveTimeHm(dateToUse);
    final drive = WorkDateUtils.resolveDriveDateForNightShift(work, timeStr);''';

  final replacement = '''    final dateToUse = originalDate ?? DateTime.now();
    var work = WorkDateUtils.effectiveWorkDateYmd(dateToUse);
    var timeStr = formatDriveTimeHm(dateToUse);
    var drive = WorkDateUtils.resolveDriveDateForNightShift(work, timeStr);

    if (_nonEmptyTrimmed(logData['drive_date'])) {
      drive = logData['drive_date'].toString().trim();
    }
    if (_nonEmptyTrimmed(logData['drive_time'])) {
      timeStr = logData['drive_time'].toString().trim();
    }
    if (_nonEmptyTrimmed(logData['drive_date']) && _nonEmptyTrimmed(logData['drive_time'])) {
      try {
        final parsedDt = DateTime.parse('\ \');
        work = WorkDateUtils.effectiveWorkDateYmd(parsedDt);
      } catch (_) {}
    }''';

  text = text.replaceFirst(target, replacement);
  f.writeAsStringSync(text);
}
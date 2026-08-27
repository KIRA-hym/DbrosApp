import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();
  
  var target = '''      if (_currentRawText != null && _currentRawText!.trim().isNotEmpty) {''';
  var replacement = '''
      // 파이어베이스(Firestore) 공유좌표 빅데이터 수집 전송 (비동기 처리)
      final String startLocCheck = _startLocCon.text.trim();
      final String endLocCheck = _endLocCon.text.trim();
      if (startLocCheck.isNotEmpty || endLocCheck.isNotEmpty) {
        OcrErrorLoggerService.instance.logSharedCallPoint(rowData: row);
      }

      if (_currentRawText != null && _currentRawText!.trim().isNotEmpty) {''';
  
  content = content.replaceFirst(target, replacement);
  file.writeAsStringSync(content);
}

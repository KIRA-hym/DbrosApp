import 'dart:io';

void main() {
  final file = File('lib/services/ocr_error_logger.dart');
  var text = file.readAsStringSync();
  
  text = text.replaceFirst(
    '''      _sessionSentHashes.add('corr_\');
      await _incrementSuccessUploadCount(prefs, todayStr);''',
    '''      _sessionSentHashes.add('corr_\');'''
  );

  file.writeAsStringSync(text);
}
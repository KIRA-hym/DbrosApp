import 'dart:io';

void main() {
  final file = File('lib/services/ocr_error_logger.dart');
  var text = file.readAsStringSync();

  // Add error limit methods
  if (!text.contains('_canUploadErrorToday')) {
      text = text.replaceFirst(
        '''  Future<bool> _canUploadSuccessToday(SharedPreferences prefs, String todayStr) async {''',
        '''  Future<bool> _canUploadErrorToday(SharedPreferences prefs, String todayStr) async {
    final countKey = 'error_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    return currentCount < 5;
  }

  Future<void> _incrementErrorUploadCount(SharedPreferences prefs, String todayStr) async {
    final countKey = 'error_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
  }

  Future<bool> _canUploadSuccessToday(SharedPreferences prefs, String todayStr) async {'''
      );
  }

  // Restore error limits in logError
  text = text.replaceFirst(
    '''      // No daily limit for error logs
      // final prefs = await SharedPreferences.getInstance();
      // final todayStr = DateTime.now().toIso8601String().substring(0, 10);''',
    '''      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      
      if (!await _canUploadErrorToday(prefs, todayStr)) {
        if (kDebugMode) print('OCR Error Log skipped due to error daily limit (5)');
        return;
      }'''
  );

  text = text.replaceFirst(
    '''      _sessionSentHashes.add(textHash);
      
      if (kDebugMode) print('OCR Error Logged to Firestore for platform: \');''',
    '''      _sessionSentHashes.add(textHash);
      await _incrementErrorUploadCount(prefs, todayStr);
      
      if (kDebugMode) print('OCR Error Logged to Firestore for platform: \');'''
  );

  // Restore error limits in logCorrection
  text = text.replaceFirst(
    '''      // No daily limit for correction logs''',
    '''      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      
      if (!await _canUploadErrorToday(prefs, todayStr)) {
        if (kDebugMode) print('OCR Correction Log skipped due to error daily limit (5)');
        return;
      }'''
  );

  text = text.replaceFirst(
    '''      _sessionSentHashes.add('corr_\');
      
      if (kDebugMode) print('OCR Correction Logged to Firestore for platform: \');''',
    '''      _sessionSentHashes.add('corr_\');
      await _incrementErrorUploadCount(prefs, todayStr);
      
      if (kDebugMode) print('OCR Correction Logged to Firestore for platform: \');'''
  );

  file.writeAsStringSync(text);
  print('Added error limits successfully');
}
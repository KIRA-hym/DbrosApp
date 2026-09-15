import 'dart:io';

void main() {
  final file = File('lib/services/ocr_error_logger.dart');
  var text = file.readAsStringSync();

  // 1. Rename the unified upload limits to success upload limits
  text = text.replaceFirst(
    '''  Future<bool> _canUploadToday(SharedPreferences prefs, String todayStr) async {
    final countKey = 'unified_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    return currentCount < 5;
  }

  Future<void> _incrementUploadCount(SharedPreferences prefs, String todayStr) async {
    final countKey = 'unified_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
  }''',
    '''  Future<bool> _canUploadSuccessToday(SharedPreferences prefs, String todayStr) async {
    final countKey = 'success_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    return currentCount < 5;
  }

  Future<void> _incrementSuccessUploadCount(SharedPreferences prefs, String todayStr) async {
    final countKey = 'success_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
  }'''
  );

  // 2. Remove limit check from logError
  text = text.replaceFirst(
    '''      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      
      if (!await _canUploadToday(prefs, todayStr)) {
        if (kDebugMode) print('OCR Error Log skipped due to unified daily limit (5)');
        return;
      }''',
    '''      // No daily limit for error logs
      // final prefs = await SharedPreferences.getInstance();
      // final todayStr = DateTime.now().toIso8601String().substring(0, 10);'''
  );

  text = text.replaceFirst(
    '''      _sessionSentHashes.add(textHash);
      await _incrementUploadCount(prefs, todayStr);''',
    '''      _sessionSentHashes.add(textHash);'''
  );

  // 3. Remove limit check from logCorrection
  text = text.replaceFirst(
    '''      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      
      if (!await _canUploadToday(prefs, todayStr)) {
        if (kDebugMode) print('OCR Correction Log skipped due to unified daily limit (5)');
        return;
      }''',
    '''      // No daily limit for correction logs'''
  );

  text = text.replaceFirst(
    '''      _sessionSentHashes.add('corr_\');
      await _incrementUploadCount(prefs, todayStr);''',
    '''      _sessionSentHashes.add('corr_\');'''
  );

  // 4. Update logSharedCallPoint to use the new success limit functions
  text = text.replaceFirst(
    '''      if (!await _canUploadToday(prefs, todayStr)) {
        if (kDebugMode) print('Shared Call Point Log skipped due to unified daily limit (5)');
        return;
      }''',
    '''      if (!await _canUploadSuccessToday(prefs, todayStr)) {
        if (kDebugMode) print('Shared Call Point Log skipped due to success daily limit (5)');
        return;
      }'''
  );

  text = text.replaceFirst(
    '''      _sessionSentHashes.add('shared_\');
      await _incrementUploadCount(prefs, todayStr);''',
    '''      _sessionSentHashes.add('shared_\');
      await _incrementSuccessUploadCount(prefs, todayStr);'''
  );

  file.writeAsStringSync(text);
  print('Changes applied successfully');
}
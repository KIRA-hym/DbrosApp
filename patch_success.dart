import 'dart:io';

void main() {
  final file = File('lib/services/ocr_error_logger.dart');
  var text = file.readAsStringSync();

  // The functions are missing. Let's insert them right after _sessionSentHashes.
  
  if (!text.contains('_canUploadSuccessToday')) {
     text = text.replaceFirst('final Set<String> _sessionSentHashes = {};', '''final Set<String> _sessionSentHashes = {};

  Future<bool> _canUploadSuccessToday(SharedPreferences prefs, String todayStr) async {
    final countKey = 'success_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    return currentCount < 5;
  }

  Future<void> _incrementSuccessUploadCount(SharedPreferences prefs, String todayStr) async {
    final countKey = 'success_upload_count_\';
    final currentCount = prefs.getInt(countKey) ?? 0;
    await prefs.setInt(countKey, currentCount + 1);
  }''');
  }

  // Check if incrementSuccessUploadCount was actually replaced in logSharedCallPoint
  if (text.contains('_incrementUploadCount(prefs, todayStr);')) {
     text = text.replaceAll('_incrementUploadCount(prefs, todayStr);', '_incrementSuccessUploadCount(prefs, todayStr);');
  }

  file.writeAsStringSync(text);
  print('Patched successfully');
}
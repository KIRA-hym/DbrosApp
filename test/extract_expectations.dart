import 'dart:io';

void main() async {
  final file = File('work/ocr_log_sample.txt');
  if (!file.existsSync()) return;

  final content = await file.readAsString();
  final blocks = content.split('───────────────────────────────────────');
  
  for (var i = 0; i < blocks.length; i++) {
    final text = blocks[i].trim();
    if (text.isEmpty) continue;
    
    if (text.contains('기대값')) {
      final startIndex = text.indexOf('기대값');
      final endIndex = text.indexOf('*/', startIndex);
      if (endIndex != -1) {
        final expectStr = text.substring(startIndex, endIndex).trim();
        // '- 정상' 이외의 문구가 있는 경우 (문제 케이스)
        if (!expectStr.contains('- 정상') || expectStr.length > 20) {
          print('--- TEST \ ---');
          print(expectStr);
        }
      }
    }
  }
}

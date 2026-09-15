import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // Find the exact lines in _buildLocationInputField
  int targetIdx = lines.indexWhere((l) => l.contains('if (labelAction != null) ...['));
  if (targetIdx != -1) {
    int sizedBoxIdx = targetIdx + 1;
    if (lines[sizedBoxIdx].contains('const SizedBox(width: 8)')) {
      lines.removeAt(sizedBoxIdx);
      file.writeAsStringSync(lines.join('\n'));
      print('Removed SizedBox(width: 8) at line \');
    } else {
      print('SizedBox(width: 8) not found at line \. Found: \');
    }
  } else {
    print('labelAction if block not found.');
  }
}

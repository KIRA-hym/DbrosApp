import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();
  
  // Insert Spacer() before SizedBox(width:8) at these 0-indexed lines
  // Line 2363 (0-indexed: 2362) and Line 2604 (0-indexed: 2603)
  // Process in REVERSE order to keep indices stable
  
  // Second occurrence: line 2604 (0-indexed 2603)
  lines.insert(2603, '                  const Spacer(),');
  
  // First occurrence: line 2363 (0-indexed 2362)  
  // After inserting above, line 2362 is still at 2362
  lines.insert(2362, '                    const Spacer(),');
  
  file.writeAsStringSync(lines.join('\n'));
  print('Done! Inserted Spacer() at lines 2363 and 2605 (1-indexed).');
}

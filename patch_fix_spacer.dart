import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();
  
  // Remove the wrongly inserted Spacer lines (at 2362 and 2604, 0-indexed)
  // After first removal, second shifts by -1
  // Line 2362 (0-indexed) = "                    const Spacer(),"
  // Line 2604 (0-indexed) = "                  const Spacer(),"
  
  // Verify they're the Spacer lines we added
  print('Line 2362: ${lines[2361]}');
  print('Line 2604: ${lines[2603]}');
  
  // Remove in reverse order
  lines.removeAt(2603);
  lines.removeAt(2361);
  
  // Now insert them AFTER the closing ), of PulseAnimationWrapper
  // (1-indexed 2363 was the Spacer, 1363 was before SizedBox)
  // The PulseAnimationWrapper closing ), is at 2-indexed 2362 (after removal)
  // 0-indexed line numbers after removal of 2361:
  // Line 2362 (new) = "                    ),"   <- this is PulseAnimationWrapper close
  // Line 2363 (new) = "                    SizedBox(width: 8),"
  
  print('After removal, line 2362: ${lines[2361]}');
  print('After removal, line 2363: ${lines[2362]}');
  
  // First location: Insert Spacer AFTER PulseAnimationWrapper ), at 0-indexed 2361
  // i.e. at position 2362
  lines.insert(2362, '                    const Spacer(),');
  
  // Second location: 0-indexed was 2603, after first insert shifts to 2604
  // After first insert + removal, the second PulseAnimationWrapper close is at:
  print('Second area, line 2604: ${lines[2603]}');
  print('Second area, line 2605: ${lines[2604]}');
  
  // Insert at 2605 (after PulseAnimationWrapper close at 2604)
  lines.insert(2605, '                  const Spacer(),');
  
  file.writeAsStringSync(lines.join('\n'));
  print('Done!');
}

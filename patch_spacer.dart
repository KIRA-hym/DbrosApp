import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // Find all occurrences of the pattern:
  // PulseAnimationWrapper(isActive: ... 'origin') followed by SizedBox(width: 8)
  // We need to insert Spacer() BEFORE the SizedBox(width: 8) that separates mic from 경유 button
  
  // Look for the closing ), of PulseAnimationWrapper for 'origin'
  // followed by SizedBox(width: 8) - these are the two origin row locations
  
  List<int> insertPositions = [];
  
  for (int i = 0; i < lines.length - 5; i++) {
    // Find "PulseAnimationWrapper" with origin nearby
    if (lines[i].contains('PulseAnimationWrapper(') && lines[i].contains('isActive:')) {
      // Check the next line for 'origin'
      if (i + 1 < lines.length && lines[i+1].contains("'origin'")) {
        // Find closing of this PulseAnimationWrapper
        int depth = 0;
        int closeIdx = i;
        for (int j = i; j < lines.length; j++) {
          for (var ch in lines[j].split('')) {
            if (ch == '(') depth++;
            if (ch == ')') depth--;
          }
          if (depth == 0) { closeIdx = j; break; }
        }
        
        // The next non-blank line after closeIdx should be SizedBox(width: 8)
        int nextLine = closeIdx + 1;
        if (nextLine < lines.length && 
            (lines[nextLine].trim().startsWith('SizedBox(width:') || 
             lines[nextLine].trim().startsWith('const SizedBox(width:'))) {
          insertPositions.add(nextLine);
          print('Will insert Spacer() at line ${nextLine+1}');
        }
      }
    }
  }
  
  print('Found ${insertPositions.length} insertion points');
  
  // Insert in reverse order to preserve line numbers
  for (int pos in insertPositions.reversed) {
    String indent = '';
    for (var c in lines[pos].split('')) {
      if (c == ' ') indent += ' '; else break;
    }
    lines.insert(pos, '${indent}const Spacer(),');
  }
  
  file.writeAsStringSync(lines.join('\n'));
  print('Done!');
}

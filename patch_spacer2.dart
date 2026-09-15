import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // Find lines that end with `),' and whose trimmed content is just '),'
  // that immediately follow a PulseAnimationWrapper block for 'origin'
  // Then check if next line is SizedBox(width: 8)
  
  List<int> insertPositions = [];
  
  for (int i = 0; i < lines.length - 3; i++) {
    // Find "PulseAnimationWrapper(" that is directly followed by "isActive: ... 'origin'"
    if (lines[i].trim() == 'PulseAnimationWrapper(' && 
        i + 1 < lines.length && lines[i+1].contains("'origin'")) {
      // Find the NEXT line that is just '),' at same or lower depth = closing of PulseAnimationWrapper
      int closeIdx = -1;
      for (int j = i + 1; j < i + 20; j++) {
        if (lines[j].trim() == '),') {
          closeIdx = j;
          break;
        }
      }
      
      if (closeIdx != -1) {
        int nextLine = closeIdx + 1;
        print('Found close at ${closeIdx+1}, next: ${lines[nextLine].trim()}');
        if (nextLine < lines.length && lines[nextLine].trim().startsWith('SizedBox(width:')) {
          insertPositions.add(nextLine);
          print('Will insert Spacer() before line ${nextLine+1}');
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

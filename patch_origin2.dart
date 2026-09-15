import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // Find all origin mic button isActive lines
  List<int> originMicLines = [];
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains("_activeSttField == 'origin'") && lines[i].contains('isActive:')) {
      originMicLines.add(i);
    }
  }
  
  print('Found origin mic blocks at lines: ${originMicLines.map((i) => i+1).toList()}');
  
  // Process in reverse order to keep line numbers stable
  for (int micLineIdx in originMicLines.reversed.toList()) {
    // Go back to find the Row's opening
    int rowStart = micLineIdx - 1;
    while (rowStart > 0 && lines[rowStart].trim() != 'Row(') rowStart--;
    
    // The children start after 'Row('
    int childrenStart = rowStart + 1;
    if (lines[childrenStart].trim() == 'children: [') childrenStart++;
    
    // Find 'Expanded(' at childrenStart
    if (lines[childrenStart].trim() == 'Expanded(') {
      int expandedStart = childrenStart;
      // Find child: Text(
      int textLine = expandedStart + 1;
      if (lines[textLine].trim() == 'child: Text(') {
        // Find the closing '),' of Expanded
        int depth = 0;
        int expandedEnd = expandedStart;
        for (int i = expandedStart; i < lines.length; i++) {
          for (var ch in lines[i].split('')) {
            if (ch == '(') depth++;
            if (ch == ')') depth--;
          }
          if (depth == 0) { expandedEnd = i; break; }
        }
        
        // Get indentation from Expanded line
        String indent = '';
        for (var c in lines[expandedStart].split('')) {
          if (c == ' ') indent += ' '; else break;
        }
        
        // Remove Expanded wrapper: blank expandedStart, fix textLine indent, blank expandedEnd
        lines[expandedStart] = '';
        lines[textLine] = lines[textLine].replaceFirst('child: Text(', '${indent}Text(');
        lines[expandedEnd] = '';
        
        // Now find PulseAnimationWrapper after expandedEnd
        int pulseStart = -1;
        for (int i = expandedEnd + 1; i < lines.length; i++) {
          if (lines[i].contains('PulseAnimationWrapper(') && lines[i].contains('isActive:')) {
            pulseStart = i;
            break;
          }
        }
        
        if (pulseStart == -1) {
          print('ERROR: Could not find PulseAnimationWrapper after line ${expandedEnd + 1}');
          continue;
        }
        
        // Find the closing , of PulseAnimationWrapper
        int pulseDepth = 0;
        int pulseEnd = pulseStart;
        for (int i = pulseStart; i < lines.length; i++) {
          for (var ch in lines[i].split('')) {
            if (ch == '(') pulseDepth++;
            if (ch == ')') pulseDepth--;
          }
          if (pulseDepth == 0) { pulseEnd = i; break; }
        }
        
        print('Pulse block: line ${pulseStart+1} to ${pulseEnd+1}');
        
        // Find SizedBox(width: 8) after pulseEnd - this is between mic and 경유 button
        int sizedBoxLine = -1;
        for (int i = pulseEnd + 1; i < pulseEnd + 5; i++) {
          if (lines[i].trim().startsWith('SizedBox(width:') || lines[i].trim().startsWith('const SizedBox(width:')) {
            sizedBoxLine = i;
            break;
          }
        }
        
        if (sizedBoxLine == -1) {
          print('ERROR: Could not find SizedBox(width:) near line ${pulseEnd + 1}');
          continue;
        }
        
        print('SizedBox(width:8) at line ${sizedBoxLine+1}');
        
        // Insert Spacer() BEFORE SizedBox(width:8) - after mic, before 경유 
        lines.insert(sizedBoxLine, '${indent}const Spacer(),');
        print('Inserted Spacer() before SizedBox at line ${sizedBoxLine+1}');
      } else {
        print('No child: Text( found at line ${textLine+1}, found: ${lines[textLine].trim()}');
      }
    } else {
      print('No Expanded( found at childrenStart line ${childrenStart+1}, found: ${lines[childrenStart].trim()}');
    }
  }
  
  file.writeAsStringSync(lines.join('\n'));
  print('Done!');
}

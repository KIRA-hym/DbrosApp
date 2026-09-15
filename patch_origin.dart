import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // =============================================
  // 수정 1: 일반 작성화면 출발지 Row (라인 ~2579)
  // =============================================
  // Find: "異쒕컻吏" row in the full form (not quick panel)
  // The pattern is: Expanded(child: Text("異쒕컻吏"...)), PulseAnimationWrapper(mic), SizedBox(width:8), GestureDetector(+경유...)
  // We need: Text("異쒕컻吏"), SizedBox(8), PulseAnimationWrapper(mic), Spacer(), GestureDetector(+경유...)

  // Find the SECOND occurrence (first is in quick-form ~2338, second is in full-form ~2579)
  int firstExpanded = lines.indexWhere((l) => l.trim() == 'Expanded(' && lines.contains('PulseAnimationWrapper('));
  
  // Let's find the two occurrences of the origin mic button block
  // Search for 'activeSttField == .origin.' pattern
  List<int> originMicLines = [];
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains("_activeSttField == 'origin'") && lines[i].contains('isActive:')) {
      originMicLines.add(i);
    }
  }
  
  print('Found origin mic blocks at lines: \');
  
  for (int micLineIdx in originMicLines) {
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
        
        // Get indentation
        String indent = '';
        for (var c in lines[expandedStart].split('')) {
          if (c == ' ') indent += ' '; else break;
        }
        
        // Get the Text content (everything from textLine to expandedEnd-1)
        // Replace: lines[expandedStart] -> '' (remove Expanded()
        //          lines[textLine] -> Text( (remove 'child: ')
        //          lines[expandedEnd] -> '' (remove closing ),)
        
        lines[expandedStart] = '';
        lines[textLine] = lines[textLine].replaceFirst('child: Text(', '\Text(');
        lines[expandedEnd] = '';
        
        print('Fixed Expanded at line \ -> \');
        
        // Now find PulseAnimationWrapper after expandedEnd and before SizedBox(width: 8)
        // We need to insert Spacer() AFTER the closing ], of the mic button
        // Find the ], that closes the mic PulseAnimationWrapper
        int pulseStart = lines.indexWhere((l) => l.contains('PulseAnimationWrapper(') && l.contains('isActive:'), expandedEnd);
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
        
        print('Pulse block: line \ to \');
        
        // Insert Spacer() between PulseAnimationWrapper and SizedBox(width:8)
        // Find SizedBox(width: 8) after pulseEnd
        int sizedBoxLine = lines.indexWhere((l) => l.trim() == 'SizedBox(width: 8),', pulseEnd);
        if (sizedBoxLine == -1) {
          sizedBoxLine = lines.indexWhere((l) => l.trim().startsWith('SizedBox(width:') && l.contains('8'), pulseEnd);
        }
        print('SizedBox(8) at line \');
        lines.insert(sizedBoxLine, '\  const Spacer(),');
        print('Inserted Spacer() before SizedBox(width:8) at line \');
      }
    }
  }
  
  file.writeAsStringSync(lines.join('\n'));
  print('Done!');
}

import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // Fix both origin mic rows:
  // Pattern: Expanded(child:Text("출발지")), PulseAnimationWrapper(mic), SizedBox(8), GestureDetector(+경유)
  // Target: Text("출발지"), PulseAnimationWrapper(mic), Spacer(), GestureDetector(+경유)
  // (Remove Expanded wrapper, remove SizedBox(8), add Spacer() after PulseAnimationWrapper)
  
  // We process in REVERSE order to keep indices stable
  // Occurrence 2: lines 2582-2625 (0-indexed 2581-2624)
  //   Expanded: 0-indexed 2581 to 2590
  //   PulseAnim close: 0-indexed 2603
  //   SizedBox(8): 0-indexed 2604
  
  // Occurrence 1: lines 2341-2384 (0-indexed 2340-2383)
  //   Expanded: 0-indexed 2340 to 2349  
  //   PulseAnim close: 0-indexed 2362
  //   SizedBox(8): 0-indexed 2363
  
  // --- Process Occurrence 2 first (higher line numbers, reverse order) ---
  // Remove Expanded wrapper (lines 2582 and 2591, 0-indexed 2581 and 2590)
  // Fix Text( indent
  // Remove SizedBox(8) (line 2605, 0-indexed 2604)
  // Add Spacer() after PulseAnim close (line 2605, 0-indexed 2604)
  
  // Step 1: Remove SizedBox(width: 8) at 0-indexed 2604
  assert(lines[2604].trim().startsWith('SizedBox(width:'), 'Expected SizedBox at 2604: ${lines[2604]}');
  lines[2604] = '                  const Spacer(),'; // Replace SizedBox with Spacer
  
  // Step 2: Remove Expanded( closing ), at 0-indexed 2590
  assert(lines[2590].trim() == '),', 'Expected ), at 2590: ${lines[2590]}');
  lines[2590] = ''; // blank out closing ), of Expanded
  
  // Step 3: Fix child: Text( -> Text( at 0-indexed 2582 -> should be text line
  // 0-indexed 2582 is "child: Text("
  assert(lines[2582].trim() == 'child: Text(', 'Expected child: Text( at 2582: ${lines[2582]}');
  lines[2582] = lines[2582].replaceFirst('child: Text(', 'Text(');
  
  // Step 4: Remove Expanded( at 0-indexed 2581
  assert(lines[2581].trim() == 'Expanded(', 'Expected Expanded( at 2581: ${lines[2581]}');
  lines[2581] = ''; // blank out Expanded(
  
  // --- Process Occurrence 1 (lower line numbers) ---
  // Step 5: Remove SizedBox(width: 8) at 0-indexed 2363
  assert(lines[2363].trim().startsWith('SizedBox(width:'), 'Expected SizedBox at 2363: ${lines[2363]}');
  lines[2363] = '                    const Spacer(),'; // Replace with Spacer
  
  // Step 6: Remove Expanded( closing ), at 0-indexed 2349
  assert(lines[2349].trim() == '),', 'Expected ), at 2349: ${lines[2349]}');
  lines[2349] = ''; // blank out closing ), of Expanded
  
  // Step 7: Fix child: Text( -> Text( at 0-indexed 2341
  assert(lines[2341].trim() == 'child: Text(', 'Expected child: Text( at 2341: ${lines[2341]}');
  lines[2341] = lines[2341].replaceFirst('child: Text(', 'Text(');
  
  // Step 8: Remove Expanded( at 0-indexed 2340
  assert(lines[2340].trim() == 'Expanded(', 'Expected Expanded( at 2340: ${lines[2340]}');
  lines[2340] = ''; // blank out Expanded(
  
  file.writeAsStringSync(lines.join('\n'));
  print('Done! Both origin mic rows fixed.');
}

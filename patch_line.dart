import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // 1. _buildLocationInputField Spacer()
  int inputStart = lines.indexWhere((l) => l.contains('Widget _buildLocationInputField('));
  int expandedIdx = lines.indexWhere((l) => l.contains('            Expanded('), inputStart);
  int textIdx = lines.indexWhere((l) => l.contains('              child: Text('), inputStart);
  lines[expandedIdx] = ''; 
  lines[textIdx] = lines[textIdx].replaceFirst('              child: Text(', '            Text(');
  int closeExpIdx = lines.indexWhere((l) => l.trim() == '),', textIdx + 5);
  lines[closeExpIdx] = '';
  
  int actionIdx = lines.indexWhere((l) => l.contains('            if (labelAction != null) ...['), inputStart);
  lines[actionIdx+1] = lines[actionIdx+1].replaceFirst('SizedBox(width: 8)', 'const SizedBox(width: 8)');
  int closeBracketIdx = lines.indexWhere((l) => l.trim() == '],', actionIdx);
  lines.insert(closeBracketIdx + 1, '            const Spacer(),');

  // 2. _buildListeningOverlay
  int buildStart = lines.indexWhere((l) => l.contains('  Widget build(BuildContext context) {'));
  lines.insert(buildStart - 1, '''  Widget _buildListeningOverlay() {
    if (!_isListening) return const SizedBox.shrink();
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _isListening ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.mic, color: Colors.redAccent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _activeSttField == 'origin' ? '출발지를 말씀해 주세요...' : '도착지를 말씀해 주세요...',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }''');

  // Re-find buildStart since we inserted lines
  buildStart = lines.indexWhere((l) => l.contains('  Widget build(BuildContext context) {'));

  // Wrap bodies in Stack!
  // Scaffold 1:
  // find ody: SafeArea(
  int scaffold1Body = lines.indexWhere((l) => l.contains('        body: SafeArea('), buildStart);
  lines[scaffold1Body] = lines[scaffold1Body].replaceFirst('        body: SafeArea(', '        body: Stack(children: [ SafeArea(');
  // find the end of this Scaffold block, which ends with       ); just before     } and     return PopScope(
  int popScopeIdx = lines.indexWhere((l) => l.contains('    return PopScope('), scaffold1Body);
  int endScaffold1 = popScopeIdx - 2; // this is the       ); line
  lines[endScaffold1] = '          if (_isListening) _buildListeningOverlay(),\n        ]),\n      );';

  // Scaffold 2:
  // find         body: SafeArea( or         body: Column(
  int scaffold2Body = lines.indexWhere((l) => l.contains('        body: '), popScopeIdx);
  // It is         body: SafeArea( or something similar
  String originalBody = lines[scaffold2Body].trim().substring(6); // e.g., "SafeArea("
  lines[scaffold2Body] = lines[scaffold2Body].replaceFirst('        body: ', '        body: Stack(children: [ ');
  // find the end of this Scaffold, which is     ); before   Widget _buildLocationInputField(
  int nextMethod = lines.indexWhere((l) => l.contains('  Widget _buildLocationInputField('), scaffold2Body);
  int endScaffold2 = nextMethod - 2; // this should be     ); for the PopScope, the line above is         ),
  // Actually, wait! In Scaffold 2, it's inside PopScope. We can just find the last         ), before     );
  // Let's just find the closing of the ody widget? That's too hard to trace.
  // Instead, wait, in Scaffold 2, does it end right before     );? Yes, the whole Scaffold ends right before     );.
  // Wait, I can just replace         ), with           if (_isListening) _buildListeningOverlay(), ], ),
  // Let me verify the exact closing lines of Scaffold 2!

  file.writeAsStringSync(lines.join('\n'));
}

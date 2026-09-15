import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var lines = file.readAsLinesSync();

  // 1. Spacer() patch
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

  // Find buildStart again
  buildStart = lines.indexWhere((l) => l.contains('  Widget build(BuildContext context) {'));

  // 3. Wrap Scaffold 1 Body
  int scaffold1Body = lines.indexWhere((l) => l.contains('        body: SafeArea('), buildStart);
  lines[scaffold1Body] = lines[scaffold1Body].replaceFirst('        body: SafeArea(', '        body: Stack(children: [ SafeArea(');
  // Find the closing of this SafeArea
  // It should be the last         ), before       ); (which closes Scaffold)
  int scaffold1Close = lines.indexWhere((l) => l.contains('      );'), scaffold1Body);
  int safeAreaClose = scaffold1Close - 1;
  while(lines[safeAreaClose].trim() != '),') { safeAreaClose--; }
  lines[safeAreaClose] = '        ), if (_isListening) _buildListeningOverlay(), ], ),';

  // 4. Wrap Scaffold 2 Body
  int scaffold2Body = lines.indexWhere((l) => l.contains('        body: ResponsiveBody('), scaffold1Close);
  lines[scaffold2Body] = lines[scaffold2Body].replaceFirst('        body: ResponsiveBody(', '        body: Stack(children: [ ResponsiveBody(');
  // Find the closing of ResponsiveBody
  int scaffold2Close = lines.indexWhere((l) => l.contains('      ),'), scaffold2Body);
  int responsiveBodyClose = scaffold2Close - 1;
  while(lines[responsiveBodyClose].trim() != '),') { responsiveBodyClose--; }
  lines[responsiveBodyClose] = '        ), if (_isListening) _buildListeningOverlay(), ], ),';

  file.writeAsStringSync(lines.join('\n'));
}

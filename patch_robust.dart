import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();

  bool changed = false;

  // 1
  if (content.contains('Expanded(') && content.contains('labelAction,')) {
    var newContent = content.replaceFirst(RegExp(r'Expanded\(\s*child: Text\(\s*label,\s*style: Theme\.of\(context\)\.textTheme\.bodySmall\?\.copyWith\(\s*color:\s*\(Theme\.of\(context\)\.textTheme\.bodySmall\?\.color \?\? Colors\.grey\),\s*\),\s*\),\s*\),'), '''Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                  ),
                ),''');
    
    newContent = newContent.replaceFirst(RegExp(r'if \(labelAction != null\) \.\.\.\[\s*SizedBox\(width: 8\),\s*labelAction,\s*\],\s*\],\s*\),'), '''if (labelAction != null) ...[
                const SizedBox(width: 8),
                labelAction,
              ],
              const Spacer(),
            ],
          ),''');
          
    if (newContent != content) {
      content = newContent;
      changed = true;
      print('Patch 1 applied');
    }
  }

  // 2
  var overlayCode = '''  Widget _buildListeningOverlay() {
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
  }

  @override
  Widget build(BuildContext context) {''';

  var newContent2 = content.replaceFirst(RegExp(r'@override\s*Widget build\(BuildContext context\) \{'), overlayCode);
  if (newContent2 != content) {
    content = newContent2;
    changed = true;
    print('Patch 2 applied');
  } else { print('Patch 2 failed'); }

  // 3
  var newContent3 = content.replaceFirst(RegExp(r'return Scaffold\(\s*backgroundColor: const Color\(0xCC000000\),'), '''return Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xCC000000),''');
  if (newContent3 != content) {
    content = newContent3;
    print('Patch 3 applied');
  } else { print('Patch 3 failed'); }

  // 4
  var newContent4 = content.replaceFirst(RegExp(r'\),\s*\),\s*\),\s*\),\s*\),\s*\),\s*\);\s*\}\s*return PopScope\('), '''          ),
                  ),
                ),
              ),
            ),
          ),
          if (_isListening) _buildListeningOverlay(),
        ],
      );
    }

    return PopScope(''');
  if (newContent4 != content) {
    content = newContent4;
    print('Patch 4 applied');
  } else { print('Patch 4 failed'); }

  // 5
  var newContent5 = content.replaceFirst(RegExp(r'child: Scaffold\(\s*backgroundColor: Theme\.of\(context\)\.scaffoldBackgroundColor,'), '''child: Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,''');
  if (newContent5 != content) {
    content = newContent5;
    print('Patch 5 applied');
  } else { print('Patch 5 failed'); }

  // 6
  var newContent6 = content.replaceFirst(RegExp(r'\);\s*\},\s*\),\s*\),\s*\),\s*\);\s*\},\s*\);\s*\}\s*Widget _buildLocationInputField\('), ''');
                  },
                ),
              ),
            ),
            if (_isListening) _buildListeningOverlay(),
          ],
        ),
      );
    }

  Widget _buildLocationInputField(''');
  if (newContent6 != content) {
    content = newContent6;
    print('Patch 6 applied');
  } else { print('Patch 6 failed'); }

  if (changed) {
    file.writeAsStringSync(content);
    print('File written.');
  }
}

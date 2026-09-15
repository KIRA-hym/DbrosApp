import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();

  final overlayCode = '''
  Widget _buildListeningOverlay() {
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

  content = content.replaceFirst(RegExp(r'@override\s+Widget build\(BuildContext context\) \{'), overlayCode);

  content = content.replaceFirst(RegExp(r'return Scaffold\(\s*backgroundColor: const Color\(0xCC000000\),'), '''return Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xCC000000),''');

  content = content.replaceFirst(RegExp(r'\),\s*\),\s*\),\s*\),\s*\),\s*\),\s*\);\s*\}\s*return PopScope\('), '''          ),
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

  content = content.replaceFirst(RegExp(r'child: Scaffold\(\s*backgroundColor: Theme.of\(context\).scaffoldBackgroundColor,'), '''child: Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,''');

  content = content.replaceFirst(RegExp(r'\);\s*\},\s*\),\s*\),\s*\),\s*\);\s*\},\s*\);\s*\}\s*Widget _buildLocationInputField\('), ''');
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

  file.writeAsStringSync(content);
  print('Done applying all changes part 2.');
}

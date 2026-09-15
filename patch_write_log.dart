import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();
  
  // 1. Fix Expanded around Text in _buildLocationInputField
  final findText1 = '''
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                  ),
                ),
              ),
            if (labelAction != null) ...[
                SizedBox(width: 8),
              labelAction,
              ],
            ],
          ),''';
  final replaceText1 = '''
          Row(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                ),
              ),
              if (labelAction != null) ...[
                const SizedBox(width: 8),
                labelAction,
              ],
            ],
          ),''';

  content = content.replaceAll(findText1, replaceText1);

  // 2. Add _buildListeningOverlay method
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
  
  content = content.replaceAll('  @override\n  Widget build(BuildContext context) {', overlayCode);

  // 3. Wrap return Scaffold(...) for fromOverlay with Stack
  final findScaffold1 = '''
      return Scaffold(
        backgroundColor: const Color(0xCC000000), // 80% 불투명 검은색으로 기존 반투명 UI 유지''';
  final replaceScaffold1 = '''
      return Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xCC000000), // 80% 불투명 검은색으로 기존 반투명 UI 유지''';
            
  content = content.replaceAll(findScaffold1, replaceScaffold1);
  
  // need to close the Stack for the first Scaffold
  final findCloseScaffold1 = '''
            ),
          ),
        );
      }

      return PopScope(''';
  final replaceCloseScaffold1 = '''
            ),
          ),
          if (_isListening) _buildListeningOverlay(),
        ],
      );
    }

    return PopScope(''';
  content = content.replaceAll(findCloseScaffold1, replaceCloseScaffold1);

  // 4. Wrap Scaffold inside PopScope with Stack
  final findPopScopeScaffold = '''
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,''';
  final replacePopScopeScaffold = '''
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,''';
  content = content.replaceAll(findPopScopeScaffold, replacePopScopeScaffold);

  // Need to close the Stack inside PopScope. 
  // It's at the very end of build method.
  // We can just find the end of the build method by looking at the last return.
  final findEndOfBuild = '''
          ),
        ),
      );
    }

  Widget _buildLocationInputField(''';
  
  final replaceEndOfBuild = '''
            ),
            if (_isListening) _buildListeningOverlay(),
          ],
        ),
      );
    }

  Widget _buildLocationInputField(''';
  
  content = content.replaceAll(findEndOfBuild, replaceEndOfBuild);

  file.writeAsStringSync(content);
  print("Patch applied.");
}

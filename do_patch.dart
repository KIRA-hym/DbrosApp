import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();
  
  // 1. Fix _buildLocationInputField Row
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
              const Spacer(),
            ],
          ),''';
  if (!content.contains(findText1)) {
    print('Failed to find findText1');
    return;
  }
  content = content.replaceAll(findText1, replaceText1);

  // 2. Add overlay method
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
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
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
  final findBuild = '  @override\n  Widget build(BuildContext context) {';
  if (!content.contains(findBuild)) {
    print('Failed to find build');
    return;
  }
  content = content.replaceAll(findBuild, overlayCode);

  // 3. First Scaffold Wrap
  final findScaffold1 = '''
      return Scaffold(
        backgroundColor: const Color(0xCC000000), // 80%''';
  final replaceScaffold1 = '''
      return Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xCC000000), // 80%''';
  if (!content.contains(findScaffold1)) {
    print('Failed to find Scaffold1');
    return;
  }
  content = content.replaceAll(findScaffold1, replaceScaffold1);

  final findCloseScaffold1 = '''
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return PopScope(''';
  final replaceCloseScaffold1 = '''
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isListening) _buildListeningOverlay(),
        ],
      );
    }

    return PopScope(''';
  if (!content.contains(findCloseScaffold1)) {
    print('Failed to find CloseScaffold1');
    return;
  }
  content = content.replaceAll(findCloseScaffold1, replaceCloseScaffold1);

  // 4. Second Scaffold Wrap
  final findScaffold2 = '''
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,''';
  final replaceScaffold2 = '''
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,''';
  if (!content.contains(findScaffold2)) {
    print('Failed to find Scaffold2');
    return;
  }
  content = content.replaceAll(findScaffold2, replaceScaffold2);

  final findCloseScaffold2 = '''
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    }

  Widget _buildLocationInputField(''';
  final replaceCloseScaffold2 = '''
                    );
                  },
                ),
              ),
            ),
            if (_isListening) _buildListeningOverlay(),
          ],
        ),
      );
    }

  Widget _buildLocationInputField(''';
  if (!content.contains(findCloseScaffold2)) {
    print('Failed to find CloseScaffold2');
    return;
  }
  content = content.replaceAll(findCloseScaffold2, replaceCloseScaffold2);

  file.writeAsStringSync(content);
  print('Done applying all changes.');
}

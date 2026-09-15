import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync().replaceAll('\r\n', '\n');

  // 1
  var find1 = '''          Row(
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
  var replace1 = '''          Row(
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

  if (!content.contains(find1)) throw Exception('find1 failed');
  content = content.replaceFirst(find1, replace1);

  // 2
  var find2 = '''  @override
  Widget build(BuildContext context) {''';
  var replace2 = '''  Widget _buildListeningOverlay() {
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

  if (!content.contains(find2)) throw Exception('find2 failed');
  content = content.replaceFirst(find2, replace2);

  // 3
  var find3 = '''      return Scaffold(
        backgroundColor: const Color(0xCC000000), // 80% 불투명 검은색으로 기존 반투명 UI 유지''';
  var replace3 = '''      return Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xCC000000), // 80% 불투명 검은색으로 기존 반투명 UI 유지''';

  if (!content.contains(find3)) throw Exception('find3 failed');
  content = content.replaceFirst(find3, replace3);

  // 4
  var find4 = '''                  ),
                ),
              ),
            ),
          ),
        );
      }

      return PopScope(''';
  var replace4 = '''                  ),
                ),
              ),
            ),
          ),
          if (_isListening) _buildListeningOverlay(),
        ],
      );
    }

    return PopScope(''';

  if (!content.contains(find4)) throw Exception('find4 failed');
  content = content.replaceFirst(find4, replace4);

  // 5
  var find5 = '''        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,''';
  var replace5 = '''        child: Stack(
          children: [
            Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,''';

  if (!content.contains(find5)) throw Exception('find5 failed');
  content = content.replaceFirst(find5, replace5);

  // 6
  var find6 = '''                  );
                },
              ),
            ),
          );
        },
      );
    }

  Widget _buildLocationInputField(''';
  var replace6 = '''                  );
                },
              ),
            ),
            if (_isListening) _buildListeningOverlay(),
          ],
        ),
      );
    }

  Widget _buildLocationInputField(''';

  if (!content.contains(find6)) throw Exception('find6 failed');
  content = content.replaceFirst(find6, replace6);

  file.writeAsStringSync(content);
  print('All 6 patches applied successfully without regex!');
}

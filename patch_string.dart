import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync().replaceAll('\r\n', '\n');

  // 1. _buildLocationInputField
  var locStart = content.indexOf('Widget _buildLocationInputField(');
  var rowStart = content.indexOf('Row(', locStart);
  var nextSizedBox = content.indexOf('SizedBox(height: 8),', rowStart);
  
  var oldRow = content.substring(rowStart, nextSizedBox);
  var newRow = '''Row(
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
        ),
        ''';
  content = content.replaceFirst(oldRow, newRow, locStart);

  // 2. _buildListeningOverlay
  var buildStart = content.indexOf('  Widget build(BuildContext context) {');
  content = content.replaceFirst('  @override\n  Widget build(BuildContext context) {', '''  Widget _buildListeningOverlay() {
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
  Widget build(BuildContext context) {''');

  // 3. First Scaffold (overlay mode)
  var firstScaffoldStart = content.indexOf('      return Scaffold(', buildStart);
  var popScopeStart = content.indexOf('    return PopScope(', firstScaffoldStart);
  var firstScaffoldBlock = content.substring(firstScaffoldStart, popScopeStart);
  
  var newFirstScaffoldBlock = firstScaffoldBlock.replaceFirst('      return Scaffold(', '''      return Stack(
        children: [
          Scaffold(''');
  
  // Replace the last       );\n    }\n\n with       );\n    }\n\n but we know it's         ),\n      );\n    }\n\n
  // We can just find the last       );
  var lastIdx = newFirstScaffoldBlock.lastIndexOf('      );\n    }\n\n');
  newFirstScaffoldBlock = newFirstScaffoldBlock.replaceRange(lastIdx, lastIdx + 9, '      ),\n          if (_isListening) _buildListeningOverlay(),\n        ],\n      );\n    }\n\n');
  content = content.replaceFirst(firstScaffoldBlock, newFirstScaffoldBlock);

  // 4. Second Scaffold (normal mode)
  var secondScaffoldStart = content.indexOf('      child: Scaffold(', popScopeStart);
  var endOfBuild = content.indexOf('  Widget _buildLocationInputField(', secondScaffoldStart);
  var secondScaffoldBlock = content.substring(secondScaffoldStart, endOfBuild);

  var newSecondScaffoldBlock = secondScaffoldBlock.replaceFirst('      child: Scaffold(', '''      child: Stack(
        children: [
          Scaffold(''');
  
  // The end is:
  //             ),
  //           ),
  //         );
  //       },
  //     );
  //   }
  // Let's replace the last         );\n      },\n    );\n  }\n\n
  // or actually           ),\n        );\n      },\n    );\n  }\n\n
  var lastIdx2 = newSecondScaffoldBlock.lastIndexOf('        );\n      },\n    );\n  }\n\n');
  newSecondScaffoldBlock = newSecondScaffoldBlock.replaceRange(lastIdx2, lastIdx2 + 11, '        ),\n        if (_isListening) _buildListeningOverlay(),\n        ],\n      );\n      },\n    );\n  }\n\n');
  
  content = content.replaceFirst(secondScaffoldBlock, newSecondScaffoldBlock);

  file.writeAsStringSync(content);
  print('String patching done!');
}


import 'dart:io';

void main() {
  final file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();
  
  final regex = RegExp(r'return TextButton\.icon\(\s*onPressed: _runAiPrecisionAnalysis,[\s\S]*?visualDensity: VisualDensity\.compact,\s*\),\s*\);');
  
  final replacement = '''return IconButton(
                      onPressed: _runAiPrecisionAnalysis,
                      icon: const Text('?', style: TextStyle(fontSize: 16)),
                      tooltip: 'AI 정밀분석',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      splashRadius: 18,
                    );''';

  content = content.replaceAll(regex, replacement);
  
  file.writeAsStringSync(content);
}


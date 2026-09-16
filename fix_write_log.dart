
import 'dart:io';

void main() {
  final file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();
  
  final targetBtn = '''return TextButton.icon(
                          onPressed: _runAiPrecisionAnalysis,
                          icon: const Text('?', style: TextStyle(fontSize: 14)),
                          label: const Text('AI 정밀분석 (무료)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        );''';
                        
  final replacementBtn = '''return IconButton(
                          onPressed: _runAiPrecisionAnalysis,
                          icon: const Text('?', style: TextStyle(fontSize: 16)),
                          tooltip: 'AI 정밀분석',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                          splashRadius: 18,
                        );''';

  final targetBtn2 = '''return TextButton.icon(
                      onPressed: _runAiPrecisionAnalysis,
                      icon: const Text('?', style: TextStyle(fontSize: 14)),
                      label: const Text('AI 정밀분석 (무료)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    );''';
                    
  final replacementBtn2 = '''return IconButton(
                      onPressed: _runAiPrecisionAnalysis,
                      icon: const Text('?', style: TextStyle(fontSize: 16)),
                      tooltip: 'AI 정밀분석',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      splashRadius: 18,
                    );''';

  content = content.replaceAll(targetBtn, replacementBtn);
  content = content.replaceAll(targetBtn2, replacementBtn2);
  
  file.writeAsStringSync(content);
}


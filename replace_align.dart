import 'dart:io';

void main() {
  final files = [
    'lib/screens/home_page.dart',
    'lib/screens/log_list_page.dart',
    'lib/screens/write_log_page.dart',
    'lib/screens/settings_page.dart',
    'lib/screens/stats_page.dart',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();
    
    // We will use a regex to match TargetFocus block and extract keyTarget and replace ContentAlign
    final regex = RegExp(r'keyTarget:\s*(_key[a-zA-Z0-9]+),([\s\S]*?)align:\s*ContentAlign\.(?:top|bottom),');
    
    content = content.replaceAllMapped(regex, (match) {
      final key = match.group(1);
      final between = match.group(2);
      // Ensure we are not matching across multiple targets (limit the between size)
      if (between!.length > 300) return match.group(0)!; 
      
      return 'keyTarget: \,\' + 'align: GuideContentWidget.getAutoAlign(\, context),';
    });
    
    file.writeAsStringSync(content);
    print('Updated \');
  }
}

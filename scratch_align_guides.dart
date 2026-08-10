import 'dart:io';

void main() {
  final files = [
    r'C:\dbros_app\lib\screens\home_page.dart',
    r'C:\dbros_app\lib\screens\log_list_page.dart',
    r'C:\dbros_app\lib\screens\stats_page.dart',
    r'C:\dbros_app\lib\screens\settings_page.dart',
    r'C:\dbros_app\lib\screens\write_log_page.dart',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();

    // 1. Strip existing alignSkip
    content = content.replaceAll(RegExp(r'\s*alignSkip:\s*Alignment\.[a-zA-Z]+,'), '');
    // Inject alignSkip before contents: [
    content = content.replaceAll(RegExp(r'(\s*)(contents:\s*\[)'), r'\1alignSkip: Alignment.bottomRight,\1\2');

    // 2. Strip existing align and customPosition inside TargetContent
    content = content.replaceAll(RegExp(r'\s*align:\s*ContentAlign\.[a-zA-Z]+,'), '');
    content = content.replaceAll(RegExp(r'\s*customPosition:\s*CustomTargetContentPosition\([^\)]*\),?'), '');
    
    // Inject align and customPosition before builder:
    content = content.replaceAll(RegExp(r'(\s*)(builder:\s*\([^\)]+\)\s*\{)'), r'\1align: ContentAlign.custom,\1customPosition: CustomTargetContentPosition(top: 0),\1\2');

    file.writeAsStringSync(content);
    print('Updated ' + path);
  }
}

import 'dart:io';
import 'dart:convert';

void refactorFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  
  var content = file.readAsStringSync(encoding: utf8);

  // Safe Color replacements
  content = content.replaceAll('const Color(0xFF121418)', 'Theme.of(context).scaffoldBackgroundColor');
  content = content.replaceAll('const Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  content = content.replaceAll('const Color(0xFFFFC700)', 'Theme.of(context).primaryColor');
  content = content.replaceAll('const Color(0xFF16181D)', 'Theme.of(context).scaffoldBackgroundColor');
  content = content.replaceAll('const Color(0xFF6E717C)', '(Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)');
  
  content = content.replaceAll('Colors.white54', '(Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)');
  content = content.replaceAll('Colors.white38', 'Theme.of(context).dividerColor');
  content = content.replaceAll('Colors.white24', 'Theme.of(context).dividerColor');
  content = content.replaceAll('Colors.white10', 'Theme.of(context).dividerColor');
  
  // Replace Colors.white but only when it's safe (not inside const styles without removing const)
  content = content.replaceAll('Colors.white', '(Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)');

  // Fix broken consts caused by dynamic Theme replacements
  content = content.replaceAll('const TextStyle(color: Theme.of(context)', 'TextStyle(color: Theme.of(context)');
  content = content.replaceAll('const TextStyle(color: (Theme.of(context)', 'TextStyle(color: (Theme.of(context)');
  content = content.replaceAll('const Icon(', 'Icon(');
  content = content.replaceAll('const Text(', 'Text(');
  content = content.replaceAll('const BoxDecoration(', 'BoxDecoration(');
  content = content.replaceAll('const BorderSide(', 'BorderSide(');
  content = content.replaceAll('const UnderlineInputBorder(', 'UnderlineInputBorder(');
  content = content.replaceAll('const InputDecoration(', 'InputDecoration(');
  
  // Do NOT blindly replace const Row/Column/SizedBox as it can break unrelated widgets
  // Let flutter analyze catch specific const errors if any remain, it's safer.
  
  file.writeAsStringSync(content, encoding: utf8);
}

void main() {
  final files = [
    'lib/screens/settings_page.dart',
    'lib/screens/home_page.dart',
    'lib/screens/write_log_page.dart',
    'lib/screens/log_list_page.dart',
    'lib/screens/stats_page.dart',
    'lib/screens/expense_list_page.dart',
    'lib/screens/expense_write_page.dart',
    'lib/screens/expense_home_page.dart',
    'lib/screens/expense_stats_page.dart',
    'lib/screens/expense_settings_page.dart',
    'lib/screens/call_point_map_page.dart',
    'lib/screens/single_call_card_page.dart',
    'lib/screens/multi_call_card_page.dart',
    'lib/widgets/home_daily_charts_panel.dart',
    'lib/widgets/bordered_section.dart',
    'lib/widgets/list_manage_dialog.dart',
  ];

  for (var file in files) {
    refactorFile(file);
  }
}

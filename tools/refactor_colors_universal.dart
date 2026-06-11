import 'dart:io';

void refactorFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  
  var content = file.readAsStringSync();

  // Color replacements
  content = content.replaceAll('const Color(0xFF121418)', 'Theme.of(context).scaffoldBackgroundColor');
  content = content.replaceAll('const Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  content = content.replaceAll('const Color(0xFFFFC700)', 'Theme.of(context).primaryColor');
  content = content.replaceAll('const Color(0xFF16181D)', 'Theme.of(context).scaffoldBackgroundColor');
  content = content.replaceAll('const Color(0xFF6E717C)', 'Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey');
  
  content = content.replaceAll('Colors.white54', 'Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey');
  content = content.replaceAll('Colors.white38', 'Theme.of(context).dividerColor');
  content = content.replaceAll('Colors.white24', 'Theme.of(context).dividerColor');
  content = content.replaceAll('Colors.white10', 'Theme.of(context).dividerColor');
  
  content = content.replaceAll('Colors.white', 'Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white');

  // Fix broken consts
  content = content.replaceAll('const TextStyle(color: Theme.of(context)', 'TextStyle(color: Theme.of(context)');
  content = content.replaceAll('const Icon(', 'Icon(');
  content = content.replaceAll('const Text(', 'Text(');
  content = content.replaceAll('const BoxDecoration(', 'BoxDecoration(');
  content = content.replaceAll('const BorderSide(', 'BorderSide(');
  content = content.replaceAll('const UnderlineInputBorder(', 'UnderlineInputBorder(');
  content = content.replaceAll('const InputDecoration(', 'InputDecoration(');
  content = content.replaceAll('const Padding(', 'Padding(');
  content = content.replaceAll('const Row(', 'Row(');
  content = content.replaceAll('const Column(', 'Column(');
  content = content.replaceAll('const Center(', 'Center(');
  content = content.replaceAll('const SizedBox(', 'SizedBox(');
  content = content.replaceAll('const Expanded(', 'Expanded(');
  content = content.replaceAll('const Container(', 'Container(');
  content = content.replaceAll('const Align(', 'Align(');
  
  file.writeAsStringSync(content);
}

void main() {
  final files = [
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

import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  content = content.replaceAll('Color color = (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)', 'Color color = const Color(0xFFFFFFFF)');
  content = content.replaceAll('Color color = Theme.of(context).primaryColor', 'Color color = const Color(0xFFFFC700)');
  content = content.replaceAll('this.color = (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)', 'this.color = const Color(0xFFFFFFFF)');
  content = content.replaceAll('this.color = Theme.of(context).primaryColor', 'this.color = const Color(0xFFFFC700)');

  // Fix any remaining `const Text` or `const Icon` that I missed
  content = content.replaceAll('const Text(', 'Text(');
  content = content.replaceAll('const Icon(', 'Icon(');
  content = content.replaceAll('const Divider(', 'Divider(');

  file.writeAsStringSync(content, encoding: utf8);
}

void main() {
  final files = [
    'lib/screens/stats_page.dart',
    'lib/screens/settings_page.dart',
    'lib/widgets/list_manage_dialog.dart',
    'lib/screens/write_log_page.dart',
    'lib/screens/home_page.dart',
    'lib/screens/log_list_page.dart',
    'lib/screens/expense_list_page.dart',
    'lib/screens/expense_stats_page.dart',
    'lib/screens/call_point_map_page.dart',
    'lib/widgets/home_daily_charts_panel.dart',
    'lib/theme/app_theme.dart',
    'lib/widgets/settings/theme_settings_section.dart',
    'lib/widgets/bordered_section.dart'
  ];

  for (var file in files) {
    fixFile(file);
  }
}

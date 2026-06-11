import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Fix BorderedSection.decoration() -> BorderedSection.decoration(context)
  content = content.replaceAll('BorderedSection.decoration()', 'BorderedSection.decoration(context)');
  
  // Fix BorderedSection.decoration(borderRadius: 12) -> BorderedSection.decoration(context, borderRadius: 12)
  content = content.replaceAll(RegExp(r'BorderedSection\.decoration\(\s*borderRadius:'), 'BorderedSection.decoration(context, borderRadius:');

  // Fix inside bordered_section.dart where it calls decoration()
  content = content.replaceAll('decoration(borderRadius: borderRadius)', 'decoration(context, borderRadius: borderRadius)');

  // Fix CardTheme -> CardThemeData in app_theme.dart
  if (path.endsWith('app_theme.dart')) {
    content = content.replaceAll('cardTheme: CardTheme(', 'cardTheme: CardThemeData(');
    content = content.replaceAll('cardTheme: const CardTheme(', 'cardTheme: CardThemeData(');
  }

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

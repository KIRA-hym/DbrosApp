import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Regex to match "?? Colors.white)70" across newlines and whitespaces
  content = content.replaceAll(RegExp(r'\?\?\s*Colors\.white\s*\)70'), '?? Colors.white).withOpacity(0.7)');
  content = content.replaceAll(RegExp(r'\?\?\s*Colors\.white\s*\)12'), '?? Colors.white).withOpacity(0.12)');
  content = content.replaceAll(RegExp(r'\?\?\s*Colors\.white\s*\)24'), '?? Colors.white).withOpacity(0.24)');
  content = content.replaceAll(RegExp(r'\?\?\s*Colors\.white\s*\)38'), '?? Colors.white).withOpacity(0.38)');
  content = content.replaceAll(RegExp(r'\?\?\s*Colors\.white\s*\)54'), '?? Colors.white).withOpacity(0.54)');

  // Fix other const array related issues that were reported
  content = content.replaceAll(RegExp(r'const\s+Divider\s*\('), 'Divider(');
  content = content.replaceAll(RegExp(r'const\s+VerticalDivider\s*\('), 'VerticalDivider(');
  content = content.replaceAll(RegExp(r'const\s+Border\s*\('), 'Border(');
  content = content.replaceAll(RegExp(r'const\s+BorderSide\s*\('), 'BorderSide(');
  content = content.replaceAll(RegExp(r'const\s+Icon\s*\('), 'Icon(');
  content = content.replaceAll(RegExp(r'const\s+Text\s*\('), 'Text(');
  content = content.replaceAll(RegExp(r'const\s+Center\s*\('), 'Center(');
  
  // Fix nested const context issues
  content = content.replaceAll(RegExp(r'Color\s+titleColor\s*=\s*\(Theme\.of\(context\)\.textTheme\.bodyLarge\?\.color\s*\?\?\s*Colors\.white\);'), 'Color titleColor = const Color(0xFFFFFFFF);');
  content = content.replaceAll(RegExp(r'Color\s+color\s*=\s*\(Theme\.of\(context\)\.textTheme\.bodyLarge\?\.color\s*\?\?\s*Colors\.white\),'), 'Color color = const Color(0xFFFFFFFF),');
  content = content.replaceAll(RegExp(r'this\.color\s*=\s*\(Theme\.of\(context\)\.textTheme\.bodyLarge\?\.color\s*\?\?\s*Colors\.white\)'), 'this.color = const Color(0xFFFFFFFF)');
  
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

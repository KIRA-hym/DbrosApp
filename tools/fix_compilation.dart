import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Fix hanging 70 and 12
  content = content.replaceAll('?? Colors.white)70', '?? Colors.white).withOpacity(0.7)');
  content = content.replaceAll('?? Colors.white)12', '?? Colors.white).withOpacity(0.12)');
  content = content.replaceAll('?? Colors.white)24', '?? Colors.white).withOpacity(0.24)');
  content = content.replaceAll('?? Colors.white)38', '?? Colors.white).withOpacity(0.38)');
  content = content.replaceAll('?? Colors.white)54', '?? Colors.white).withOpacity(0.54)');

  // Fix const violations
  content = content.replaceAll('const Divider(color:', 'Divider(color:');
  content = content.replaceAll('const VerticalDivider(width: 1, color:', 'VerticalDivider(width: 1, color:');
  content = content.replaceAll('const Border(bottom: BorderSide(color:', 'Border(bottom: BorderSide(color:');
  content = content.replaceAll('const Icon(Icons.label, color:', 'Icon(Icons.label, color:');
  content = content.replaceAll('const Icon(Icons.delete, color:', 'Icon(Icons.delete, color:');
  content = content.replaceAll('const Center(child: Text', 'Center(child: Text');
  content = content.replaceAll('const Text(', 'Text(');
  content = content.replaceAll('const Icon(', 'Icon(');

  // Fix context not found / default param violations
  content = content.replaceAll('Color titleColor = (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)', 'Color titleColor = const Color(0xFFFFFFFF)');
  content = content.replaceAll('Color accentColor = Theme.of(context).primaryColor', 'Color accentColor = const Color(0xFFFFC700)');
  content = content.replaceAll('this.accentColor = Theme.of(context).primaryColor', 'this.accentColor = const Color(0xFFFFC700)');

  // Fix CardTheme assignment in app_theme.dart
  content = content.replaceAll('cardTheme: CardTheme(', 'cardTheme: const CardTheme(');
  content = content.replaceAll('cardTheme: const const', 'cardTheme: const');

  // Fix BorderedSection.decoration(context, borderRadius: 12)
  content = content.replaceAll('BorderedSection.decoration(context, borderRadius: 12)', 'BorderedSection.decoration(context)');

  // Fix LineChartPainter context issue in stats_page.dart
  content = content.replaceAll('..color = Theme.of(context).primaryColor', '..color = const Color(0xFFFFC700)');

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

import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  final widgetsToUnconst = [
    'Column', 'Row', 'Padding', 'Align', 'Container', 'Expanded', 'Center',
    'SizedBox', 'Icon', 'Text', 'RichText', 'Drawer', 'Scaffold', 'AppBar',
    'Divider', 'VerticalDivider', 'CircularProgressIndicator', 'Border', 'BorderSide',
    'EdgeInsets', 'BorderRadius', 'TextStyle', 'FractionallySizedBox'
  ];

  for (final w in widgetsToUnconst) {
    content = content.replaceAll('const $w(', '$w(');
  }

  content = content.replaceAll('const [', '[');
  content = content.replaceAll('const <Widget>[', '<Widget>[');
  
  // also handle "const {" for sets or maps if they exist, though rare for UI
  // content = content.replaceAll('const {', '{');

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

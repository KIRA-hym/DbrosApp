import 'dart:io';
void main() {
  final homeFile = File(r'C:\dbros_app\lib\screens\home_page.dart');
  var home = homeFile.readAsStringSync();
  home = home.replaceAll(RegExp(r'if\s*\(mounted\)\s*mainTabEventController\.add\(4\);'), 'Future.delayed(const Duration(milliseconds: 300), () { if (mounted) mainTabEventController.add(4); });');
  homeFile.writeAsStringSync(home);

  final statsFile = File(r'C:\dbros_app\lib\screens\stats_page.dart');
  var stats = statsFile.readAsStringSync();
  stats = stats.replaceAll(RegExp(r'if\s*\(mounted\)\s*mainTabEventController\.add\(4\);'), 'Future.delayed(const Duration(milliseconds: 300), () { if (mounted) mainTabEventController.add(4); });');
  statsFile.writeAsStringSync(stats);

  final settingsFile = File(r'C:\dbros_app\lib\screens\settings_page.dart');
  var settings = settingsFile.readAsStringSync();
  settings = settings.replaceAll(RegExp(r'return\s+SingleChildScrollView\(\s*padding:\s*EdgeInsets\.all\(horizontalPadding\)'), 'return SingleChildScrollView(\n        controller: _scrollController,\n        padding: EdgeInsets.all(horizontalPadding)');
  settingsFile.writeAsStringSync(settings);

  print('Done fixing bugs!');
}

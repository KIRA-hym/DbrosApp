import 'dart:io';
void main() {
  final file = File(r'C:\dbros_app\lib\screens\settings_page.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('final ScrollController _scrollController')) {
    content = content.replaceFirst("class _SettingsPageState extends State<SettingsPage> {", "class _SettingsPageState extends State<SettingsPage> {\n  final ScrollController _scrollController = ScrollController();");
  }
  
  if (!content.contains('_scrollController.dispose()')) {
    content = content.replaceFirst("  void dispose() {", "  void dispose() {\n    _scrollController.dispose();");
  }
  
  file.writeAsStringSync(content);
  print('Done.');
}

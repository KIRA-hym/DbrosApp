import 'dart:io';
void main() {
  final file = File('lib/screens/home_page.dart');
  var content = file.readAsStringSync();
  if (!content.contains('bool _hasMapUpdate = false;')) {
    content = content.replaceFirst(
      "class _HomePageState extends State<HomePage> with WidgetsBindingObserver {",
      "class _HomePageState extends State<HomePage> with WidgetsBindingObserver {\n  bool _hasMapUpdate = false;"
    );
    file.writeAsStringSync(content);
  }
}
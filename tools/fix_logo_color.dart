import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('lib/screens/home_page.dart');
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  content = content.replaceFirst(
    "Image.asset(\n                  'assets/title.png',\n                  fit: BoxFit.contain,\n                ),",
    "Image.asset(\n                  'assets/title.png',\n                  fit: BoxFit.contain,\n                  color: Theme.of(context).brightness == Brightness.light ? Theme.of(context).textTheme.bodyLarge?.color : null,\n                ),"
  );

  file.writeAsStringSync(content, encoding: utf8);
}

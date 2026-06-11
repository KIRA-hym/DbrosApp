import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Fix YouTube section placeholder background
  if (path.endsWith('home_page.dart')) {
    content = content.replaceAll(
      'color: Theme.of(context).scaffoldBackgroundColor,',
      'color: Theme.of(context).cardTheme.color!,'
    );
  }

  file.writeAsStringSync(content, encoding: utf8);
}

void main() {
  fixFile('lib/screens/home_page.dart');
}

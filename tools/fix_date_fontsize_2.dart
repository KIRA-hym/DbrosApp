import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('lib/screens/home_page.dart');
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  content = content.replaceFirst(
    'fontSize: 18,\n                        fontWeight: FontWeight.bold,',
    'fontSize: 17,\n                        fontWeight: FontWeight.bold,'
  );

  file.writeAsStringSync(content, encoding: utf8);
}

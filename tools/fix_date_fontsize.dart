import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('lib/screens/home_page.dart');
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  content = content.replaceFirst(
    'Text(\n                      dateFull,\n                      style: TextStyle(\n                        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),\n                        fontSize: 14,\n                        fontWeight: FontWeight.w500,\n                      ),\n                    ),',
    'Text(\n                      dateFull,\n                      style: TextStyle(\n                        color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),\n                        fontSize: 18,\n                        fontWeight: FontWeight.bold,\n                      ),\n                    ),'
  );

  file.writeAsStringSync(content, encoding: utf8);
}

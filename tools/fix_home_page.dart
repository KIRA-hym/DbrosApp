import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Replace hardcoded border colors in home_page.dart and notice_list_page.dart
  content = content.replaceAll('border: Border.all(color: const Color(0xFF2C2F36))', 'border: Border.all(color: Theme.of(context).dividerColor)');
  
  // Fix today's date font size and weight in home_page.dart
  if (path.endsWith('home_page.dart')) {
    content = content.replaceAll(
      'fontSize: 14,\n                        fontWeight: FontWeight.w500,',
      'fontSize: 15,\n                        fontWeight: FontWeight.bold,'
    );
  }

  file.writeAsStringSync(content, encoding: utf8);
}

void main() {
  final files = [
    'lib/screens/home_page.dart',
    'lib/screens/notice_list_page.dart'
  ];
  for (var p in files) {
    fixFile(p);
  }
}

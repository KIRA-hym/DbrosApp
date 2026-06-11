import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Replace hardcoded dark backgrounds
  content = content.replaceAll('Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  content = content.replaceAll('const Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  
  // Replace hardcoded selected state color
  content = content.replaceAll('const Color(0xFF2A2E38)', '(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))');
  content = content.replaceAll('Color(0xFF2A2E38)', '(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))');

  // Fix dividerColor not set in app_theme.dart
  if (path.endsWith('app_theme.dart')) {
    content = content.replaceAll('dividerTheme: const DividerThemeData(\n        color: Color(0xFF2C2F38),', 'dividerColor: const Color(0xFF2C2F38),\n      dividerTheme: const DividerThemeData(\n        color: Color(0xFF2C2F38),');
    content = content.replaceAll('dividerTheme: const DividerThemeData(\n        color: Color(0xFFE5E7EB),', 'dividerColor: const Color(0xFFE5E7EB),\n      dividerTheme: const DividerThemeData(\n        color: Color(0xFFE5E7EB),');
  }

  // Also fix the ? icon circle color in write_log_page.dart
  if (path.endsWith('write_log_page.dart')) {
    content = content.replaceAll('color: Theme.of(context).dividerColor,', 'color: Theme.of(context).dividerColor,'); // Actually dividerColor should work now that we explicitly add it to ThemeData
  }

  file.writeAsStringSync(content, encoding: utf8);
}

void main() {
  final dir = Directory('lib');
  for (var f in dir.listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart')) {
      fixFile(f.path);
    }
  }
}

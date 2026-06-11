import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Replace hardcoded dark backgrounds
  content = content.replaceAll('Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  content = content.replaceAll('const Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  
  // Fix dividerColor not set in app_theme.dart
  if (path.endsWith('app_theme.dart')) {
    content = content.replaceAll('dividerTheme: const DividerThemeData(\n        color: Color(0xFF2C2F38),', 'dividerColor: const Color(0xFF2C2F38),\n      dividerTheme: const DividerThemeData(\n        color: Color(0xFF2C2F38),');
    content = content.replaceAll('dividerTheme: const DividerThemeData(\n        color: Color(0xFFE5E7EB),', 'dividerColor: const Color(0xFFE5E7EB),\n      dividerTheme: const DividerThemeData(\n        color: Color(0xFFE5E7EB),');
  }

  // Also fix write_log_page.dart specifically if it has hardcoded icons that need contrast
  if (path.endsWith('write_log_page.dart')) {
    // The user mentioned "?아이콘도 라이트모드에맞게" (The ? icon).
    // The background is Theme.of(context).dividerColor, which we just fixed.
    // However, if there are other hardcoded dark shapes, let's fix them too.
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

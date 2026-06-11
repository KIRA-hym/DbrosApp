import 'dart:io';
import 'dart:convert';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Fix AppColors
  if (path.endsWith('app_colors.dart')) {
    content = content.replaceAll('static const Color surface = Theme.of(context).cardTheme.color!;', 'static const Color surface = Color(0xFF1F222A);');
  }

  // Fix app_theme.dart
  if (path.endsWith('app_theme.dart')) {
    content = content.replaceAll('surface: Theme.of(context).cardTheme.color!,', 'surface: const Color(0xFF1F222A),');
    content = content.replaceAll('backgroundColor: Theme.of(context).cardTheme.color!,', 'backgroundColor: const Color(0xFF1F222A),');
    content = content.replaceAll('color: const Theme.of(context).cardTheme.color!,', 'color: const Color(0xFF1F222A),');
  }

  // Fix const Theme.of
  content = content.replaceAll('const Theme.of(context).cardTheme.color!', 'Theme.of(context).cardTheme.color!');
  
  // Fix nested Theme.of caused by double regex replacement
  // The bad string is:
  // (Theme.of(context).brightness == Brightness.dark ? const (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4)) : const Color(0xFFFFF3C4))
  // We'll use a regex to catch any double replacements.
  content = content.replaceAll(
    '(Theme.of(context).brightness == Brightness.dark ? const (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4)) : const Color(0xFFFFF3C4))', 
    '(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))'
  );
  content = content.replaceAll(
    '(Theme.of(context).brightness == Brightness.dark ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4)) : const Color(0xFFFFF3C4))', 
    '(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))'
  );
  // Also clean up if there's "const (Theme.of"
  content = content.replaceAll('const (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))', '(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))');
  
  // Actually, let's just globally replace the mess if it's slightly different
  content = content.replaceAll(RegExp(r'\(\s*Theme\.of\(context\)\.brightness\s*==\s*Brightness\.dark\s*\?\s*const\s*\(\s*Theme\.of\(context\)\.brightness\s*==\s*Brightness\.dark\s*\?\s*const\s*Color\(0xFF2A2E38\)\s*:\s*const\s*Color\(0xFFFFF3C4\)\s*\)\s*:\s*const\s*Color\(0xFFFFF3C4\)\s*\)'), '(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2E38) : const Color(0xFFFFF3C4))');

  // Also replace `const BorderSide(color: (Theme.of(context)`
  content = content.replaceAll('const BorderSide(color: (Theme.of(context)', 'BorderSide(color: (Theme.of(context)');
  
  // Check expense_write_page.dart:242
  // colorScheme: const ColorScheme.dark(primary: Color(0xFFFFC700), surface: Theme.of(context).cardTheme.color!),
  content = content.replaceAll('const ColorScheme.dark(primary: Color(0xFFFFC700), surface: Theme.of(context).cardTheme.color!)', 'ColorScheme.dark(primary: const Color(0xFFFFC700), surface: Theme.of(context).cardTheme.color!)');

  // Let's do one more pass to remove any remaining "const Theme.of("
  content = content.replaceAll('const Theme.of(', 'Theme.of(');

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

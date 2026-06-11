import 'dart:io';

void main() {
  final file = File('lib/screens/settings_page.dart');
  var content = file.readAsStringSync();

  // Color replacements
  content = content.replaceAll('const Color(0xFF121418)', 'Theme.of(context).scaffoldBackgroundColor');
  content = content.replaceAll('const Color(0xFF1F222A)', 'Theme.of(context).cardTheme.color!');
  content = content.replaceAll('const Color(0xFFFFC700)', 'Theme.of(context).primaryColor');
  content = content.replaceAll('const Color(0xFF16181D)', 'Theme.of(context).scaffoldBackgroundColor');
  content = content.replaceAll('const Color(0xFF6E717C)', 'Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey');
  
  content = content.replaceAll('Colors.white54', 'Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey');
  content = content.replaceAll('Colors.white38', 'Theme.of(context).dividerColor');
  content = content.replaceAll('Colors.white24', 'Theme.of(context).dividerColor');
  content = content.replaceAll('Colors.white10', 'Theme.of(context).dividerColor');
  
  // Replace Colors.white but only when it's safe (not inside const styles without removing const)
  // We'll just replace Colors.white with Theme.of(context).textTheme.bodyLarge?.color
  content = content.replaceAll('Colors.white', 'Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white');

  // Now fix broken consts
  // "const TextStyle(color: Theme.of(context)...)" -> "TextStyle(color: Theme.of(context)...)"
  content = content.replaceAll('const TextStyle(color: Theme.of(context)', 'TextStyle(color: Theme.of(context)');
  // "const Icon(icon, color: Theme.of(context)" -> "Icon(icon, color: Theme.of(context)"
  content = content.replaceAll('const Icon(', 'Icon(');
  content = content.replaceAll('const Text(', 'Text(');
  content = content.replaceAll('const BoxDecoration(', 'BoxDecoration(');
  content = content.replaceAll('const BorderSide(', 'BorderSide(');
  content = content.replaceAll('const UnderlineInputBorder(', 'UnderlineInputBorder(');
  content = content.replaceAll('const InputDecoration(', 'InputDecoration(');
  
  // Just in case we broke true consts, we will let flutter analyze catch them, but most are fine to be non-const in Flutter
  file.writeAsStringSync(content);
}

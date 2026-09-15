import 'dart:io';
void main() {
  final file = File('lib/services/settings_service.dart');
  var content = file.readAsStringSync();
  content = content.trimRight();
  if (content.endsWith('}')) {
    content = content.substring(0, content.length - 1) + "  static int get localCallPointVersion => _prefs.getInt('localCallPointVersion') ?? 0;\n  static Future<void> setLocalCallPointVersion(int value) async => await _prefs.setInt('localCallPointVersion', value);\n}\n";
    file.writeAsStringSync(content);
  }
}
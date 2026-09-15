import 'dart:io';
void main() {
  final file = File('lib/services/settings_service.dart');
  var content = file.readAsStringSync();
  content = content.replaceFirst(
    "}\n",
    "  static int get localCallPointVersion => _prefs.getInt('localCallPointVersion') ?? 0;\n  static Future<void> setLocalCallPointVersion(int value) async => await _prefs.setInt('localCallPointVersion', value);\n}\n"
  );
  file.writeAsStringSync(content);
}
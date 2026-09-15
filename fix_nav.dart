import 'dart:io';
void main() {
  final file = File('lib/screens/home_page.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(
    'MaterialPageRoute(builder: (_) => const CallPointMapPage()),',
    'MaterialPageRoute(builder: (_) => const CallPointMapPage()),\n                    ).then((_) => _checkMapUpdate());\n//'
  );
  file.writeAsStringSync(content);
}
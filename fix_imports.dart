import 'dart:io';

void main() {
  var file = File('lib/screens/stats_page.dart');
  var c = file.readAsStringSync();
  
  if (!c.contains("import '../utils/pro_feature_guard.dart';")) {
    c = "import '../utils/pro_feature_guard.dart';\nimport '../services/feature_usage_service.dart';\n" + c;
    file.writeAsStringSync(c);
    print('Imports added successfully.');
  } else {
    print('Imports already exist.');
  }
}

import 'dart:io';

void main() {
  final logList = File(r'C:\dbros_app\lib\screens\log_list_page.dart');
  var content = logList.readAsStringSync();
  
  // 1. Add import
  if (!content.contains("import '../main_navigation.dart';")) {
      content = content.replaceAll("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../main_navigation.dart';");
  }
  
  // 2. Add popUntil logic
  final onFinishSkip = '''      onFinish: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
          mainTabEventController.add(4);
        });
        return true;
      },
      onSkip: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
          mainTabEventController.add(4);
        });
        return true;
      },
''';
  content = content.replaceAll("      opacityShadow: 0.8,\n    ).show(context: context);", "      opacityShadow: 0.8,\n" + onFinishSkip + "    ).show(context: context);");
  
  logList.writeAsStringSync(content);
  print('Updated log_list_page.dart');
}

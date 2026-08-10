import 'dart:io';
void main() {
  final homePath = r'C:\dbros_app\lib\screens\home_page.dart';
  var home = File(homePath).readAsStringSync();
  
  if (!home.contains("import '../widgets/onboarding_dialog.dart';")) {
    home = home.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../widgets/onboarding_dialog.dart';");
  }
  
  if (!home.contains('OnboardingDialog.showIfNeeded')) {
    home = home.replaceFirst('PermissionDisclosureDialog.showIfNeeded(context);', 'PermissionDisclosureDialog.showIfNeeded(context);\n          OnboardingDialog.showIfNeeded(context);');
  }
  
  File(homePath).writeAsStringSync(home);
  print('Onboarding call injected.');
}

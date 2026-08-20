import 'dart:io';

void main() {
  final file = File('lib/widgets/list_manage_dialog.dart');
  String code = file.readAsStringSync();

  // Add import if missing
  if (!code.contains("import 'app_glass_dialog.dart';")) {
    code = code.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'app_glass_dialog.dart';");
  }

  // Replace Align( TextButton( 닫기 ) ) with GlassDialogConfirmButton
  final oldCloseBtn = '''Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('닫기', style: TextStyle(color: Color(0xFF9FA3AE))),
                  ),
                ),''';
                
  final newCloseBtn = '''Align(
                  alignment: Alignment.centerRight,
                  child: GlassDialogConfirmButton(
                    label: '닫기',
                    filled: true,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),''';

  if (code.contains(oldCloseBtn)) {
    code = code.replaceFirst(oldCloseBtn, newCloseBtn);
    print("Replaced close button in ListManageDialog.");
  } else {
    print("Could not find close button in ListManageDialog.");
    // Try a more flexible search
    final pattern = RegExp(r"Align\(\s*alignment:\s*Alignment\.centerRight,\s*child:\s*TextButton\(\s*onPressed:\s*\(\)\s*=>\s*Navigator\.pop\(context\),\s*child:\s*Text\('닫기'[^)]+\),\s*\),\s*\),");
    if (pattern.hasMatch(code)) {
      code = code.replaceFirst(pattern, newCloseBtn);
      print("Replaced close button using Regex.");
    }
  }

  file.writeAsStringSync(code);
}

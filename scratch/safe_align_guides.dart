import 'dart:io';

void main() {
  final files = [
    r'C:\dbros_app\lib\screens\home_page.dart',
    r'C:\dbros_app\lib\screens\log_list_page.dart',
    r'C:\dbros_app\lib\screens\stats_page.dart',
    r'C:\dbros_app\lib\screens\settings_page.dart',
    r'C:\dbros_app\lib\screens\write_log_page.dart',
  ];

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();

    content = content.replaceAllMapped(RegExp(r'(TargetFocus\s*\()([\s\S]*?)(contents:\s*\[)'), (match) {
      var props = match.group(2)!;
      props = props.replaceAll(RegExp(r'\s*alignSkip:\s*Alignment\.[a-zA-Z]+,'), '');
      return '${match.group(1)}$props  alignSkip: Alignment.bottomRight,\n  ${match.group(3)}';
    });

    content = content.replaceAllMapped(RegExp(r'(TargetContent\s*\()([\s\S]*?)(builder:\s*\([^\)]+\)\s*\{)'), (match) {
      var props = match.group(2)!;
      props = props.replaceAll(RegExp(r'\s*align:\s*ContentAlign\.[a-zA-Z]+,'), '');
      props = props.replaceAll(RegExp(r'\s*customPosition:\s*CustomTargetContentPosition\([^\)]*\),?'), '');
      return '${match.group(1)}$props  align: ContentAlign.custom,\n  customPosition: CustomTargetContentPosition(top: 0),\n  ${match.group(3)}';
    });
    
    if (path.contains('home_page.dart')) {
      final oldInit = '    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) {\n        PermissionDisclosureDialog.showIfNeeded(context);';
      final newInit = '    WidgetsBinding.instance.addPostFrameCallback((_) async {\n      if (mounted) {\n        await PermissionDisclosureDialog.showIfNeeded(context);\n        if (mounted) {\n          await OnboardingDialog.showIfNeeded(context);\n        }';
      content = content.replaceAll(oldInit, newInit);
      if (!content.contains("import '../widgets/onboarding_dialog.dart';")) {
        content = content.replaceAll(
          "import '../widgets/permission_disclosure_dialog.dart';",
          "import '../widgets/permission_disclosure_dialog.dart';\nimport '../widgets/onboarding_dialog.dart';"
        );
      }
    }

    file.writeAsStringSync(content);
    print('Updated ' + path);
  }
}

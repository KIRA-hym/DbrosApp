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

    // 1. TargetFocus alignSkip
    content = content.replaceAllMapped(RegExp(r'(TargetFocus\s*\()([\s\S]*?)(contents:\s*\[)'), (match) {
      var props = match.group(2)!;
      props = props.replaceAll(RegExp(r'\s*alignSkip:\s*Alignment\.[a-zA-Z]+,'), '');
      return '${match.group(1)}$props  alignSkip: Alignment.bottomRight,\n  ${match.group(3)}';
    });

    // 2. TargetContent align & customPosition
    content = content.replaceAllMapped(RegExp(r'(TargetContent\s*\()([\s\S]*?)(builder:\s*\([^\)]+\)\s*\{)'), (match) {
      var props = match.group(2)!;
      props = props.replaceAll(RegExp(r'\s*align:\s*ContentAlign\.[a-zA-Z]+,'), '');
      props = props.replaceAll(RegExp(r'\s*customPosition:\s*CustomTargetContentPosition\([^\)]*\),?'), '');
      return '${match.group(1)}$props  align: ContentAlign.custom,\n  customPosition: CustomTargetContentPosition(top: 0),\n  ${match.group(3)}';
    });
    
    // 3. Fix nav issues for write_log_page and log_list_page
    final replaceFinish = '''
        onFinish: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            mainTabEventController.add(4);
          });
          return true;
        },
''';
    final replaceSkip = replaceFinish.replaceAll('onFinish', 'onSkip');

    if (path.contains('write_log_page.dart')) {
      final targetFinish = '''
        onFinish: () {
          final nav = Navigator.of(context, rootNavigator: true);
          final canPop = nav.canPop();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (canPop) {
              nav.pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';
      content = content.replaceAll(targetFinish, replaceFinish);
      content = content.replaceAll(targetFinish.replaceAll('onFinish', 'onSkip'), replaceSkip);
        
      // Update OCR terms
      content = content.replaceAll('OCR(자동 인식)', '콜카드 인식(자동 입력)');
      content = content.replaceAll('OCR(자동 인식) 이용 안내', '콜카드 인식(자동 입력) 이용 안내');
      content = content.replaceAll('OCR 기능은', '콜카드 인식 기능은');
      content = content.replaceAll('콜카드 이미지 자동 인식', '콜카드 인식(자동 입력)');
    }

    if (path.contains('log_list_page.dart')) {
      final regexFinish = RegExp(r'onFinish:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\}');
      final replaceFinishStr = '''onFinish: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            mainTabEventController.add(4);
          });
          return true;
        }''';
      final regexSkip = RegExp(r'onSkip:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\}');
      final replaceSkipStr = replaceFinishStr.replaceAll('onFinish', 'onSkip');

      content = content.replaceAll(regexFinish, replaceFinishStr);
      content = content.replaceAll(regexSkip, replaceSkipStr);
    }
    
    // 4. Add Onboarding logic to home_page.dart
    if (path.contains('home_page.dart')) {
      final oldInit = '''    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PermissionDisclosureDialog.showIfNeeded(context);''';
      final newInit = '''    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await PermissionDisclosureDialog.showIfNeeded(context);
        if (mounted) {
          await OnboardingDialog.showIfNeeded(context);
        }''';
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

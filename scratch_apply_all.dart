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

    // 1. Strip existing alignSkip
    content = content.replaceAll(RegExp(r'\s*alignSkip:\s*Alignment\.[a-zA-Z]+,'), '');
    // Inject alignSkip before contents: [
    content = content.replaceAllMapped(RegExp(r'(\s*)(contents:\s*\[)'), (match) {
      return '${match.group(1)}alignSkip: Alignment.bottomRight,${match.group(1)}${match.group(2)}';
    });

    // 2. Strip existing align and customPosition inside TargetContent
    content = content.replaceAll(RegExp(r'\s*align:\s*ContentAlign\.[a-zA-Z]+,'), '');
    content = content.replaceAll(RegExp(r'\s*customPosition:\s*CustomTargetContentPosition\([^\)]*\),?'), '');
    
    // Inject align and customPosition before builder:
    content = content.replaceAllMapped(RegExp(r'(\s*)(builder:\s*\([^\)]+\)\s*\{)'), (match) {
      return '${match.group(1)}align: ContentAlign.custom,${match.group(1)}customPosition: CustomTargetContentPosition(top: 0),${match.group(1)}${match.group(2)}';
    });
    
    // 3. Fix nav issues for write_log_page and log_list_page
    if (path.contains('write_log_page.dart')) {
      final targetFinish = '''
        onFinish: () {
          final route = ModalRoute.of(context);
          final isPushed = route != null && !route.isFirst;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isPushed && route.isActive) {
              Navigator.of(context, rootNavigator: true).removeRoute(route);
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';
      final replaceFinish = '''
        onFinish: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            mainTabEventController.add(4);
          });
          return true;
        },
''';
      content = content.replaceAll(targetFinish, replaceFinish);
      content = content.replaceAll(targetFinish.replaceAll('onFinish', 'onSkip'), replaceFinish.replaceAll('onFinish', 'onSkip'));
      
      // Try older patterns just in case
      final oldFinish1 = '''
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
      content = content.replaceAll(oldFinish1, replaceFinish);
      content = content.replaceAll(oldFinish1.replaceAll('onFinish', 'onSkip'), replaceFinish.replaceAll('onFinish', 'onSkip'));
    }

    if (path.contains('log_list_page.dart')) {
      final regexFinish = RegExp(r'onFinish:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\}');
      final replaceFinish = '''onFinish: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            mainTabEventController.add(4);
          });
          return true;
        }''';

      final regexSkip = RegExp(r'onSkip:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\}');
      final replaceSkip = '''onSkip: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            mainTabEventController.add(4);
          });
          return true;
        }''';

      content = content.replaceAll(regexFinish, replaceFinish);
      content = content.replaceAll(regexSkip, replaceSkip);
    }

    file.writeAsStringSync(content);
    print('Updated ' + path);
  }
}

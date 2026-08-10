import 'dart:io';

void main() {
  final path = r'C:\dbros_app\lib\screens\log_list_page.dart';
  var content = File(path).readAsStringSync();

  // Find all instances of this specific onFinish and replace them.
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

  File(path).writeAsStringSync(content);
  print('Done replace!');
}

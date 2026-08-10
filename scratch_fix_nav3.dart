import 'dart:io';

void main() {
  final path = r'C:\dbros_app\lib\screens\write_log_page.dart';
  var content = File(path).readAsStringSync();

  final targetFinish = '''
        onFinish: () {
          final isDetailMode = _logId != null || widget.initialDate != null;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isDetailMode) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  final replaceFinish = '''
        onFinish: () {
          final canPop = Navigator.of(context).canPop();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (canPop) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  final targetSkip = '''
        onSkip: () {
          final isDetailMode = _logId != null || widget.initialDate != null;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isDetailMode) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  final replaceSkip = '''
        onSkip: () {
          final canPop = Navigator.of(context).canPop();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (canPop) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  content = content.replaceAll(targetFinish, replaceFinish);
  content = content.replaceAll(targetSkip, replaceSkip);

  File(path).writeAsStringSync(content);
  print('Done.');
}

import 'dart:io';

void main() {
  final path = r'C:\dbros_app\lib\screens\write_log_page.dart';
  var content = File(path).readAsStringSync();

  final targetFinish = '''
        onFinish: () {
          final isPushed = !(ModalRoute.of(context)?.isFirst ?? true);
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isPushed) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  final replaceFinish = '''
        onFinish: () {
          final isPushed = !(ModalRoute.of(context)?.isFirst ?? true);
          print('onFinish called! isPushed: \, isFirst: \');
          Future.delayed(const Duration(milliseconds: 300), () {
            print('Future.delayed executing. Calling pop if isPushed is true.');
            if (isPushed) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  final targetSkip = '''
        onSkip: () {
          final isPushed = !(ModalRoute.of(context)?.isFirst ?? true);
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isPushed) {
              Navigator.of(context).pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },
''';

  final replaceSkip = '''
        onSkip: () {
          final isPushed = !(ModalRoute.of(context)?.isFirst ?? true);
          print('onSkip called! isPushed: \, isFirst: \');
          Future.delayed(const Duration(milliseconds: 300), () {
            print('Future.delayed executing. Calling pop if isPushed is true.');
            if (isPushed) {
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

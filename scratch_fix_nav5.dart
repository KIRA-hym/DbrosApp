import 'dart:io';

void main() {
  final path = r'C:\dbros_app\lib\screens\write_log_page.dart';
  var content = File(path).readAsStringSync();

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

  final replaceFinish = '''
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

  final targetSkip = '''
        onSkip: () {
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

  final replaceSkip = '''
        onSkip: () {
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

  content = content.replaceAll(targetFinish, replaceFinish);
  content = content.replaceAll(targetSkip, replaceSkip);

  File(path).writeAsStringSync(content);
  print('Done.');
}

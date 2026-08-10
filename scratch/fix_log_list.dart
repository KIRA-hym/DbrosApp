import 'dart:io';
void main() {
  final file = File(r'C:\dbros_app\lib\screens\log_list_page.dart');
  var content = file.readAsStringSync();
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
  content = content.replaceAll(").show(context: context);", onFinishSkip + "    ).show(context: context);");
  file.writeAsStringSync(content);
}

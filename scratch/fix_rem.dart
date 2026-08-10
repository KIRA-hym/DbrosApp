import 'dart:io';

void main() {
  final files = [
    (r'C:\dbros_app\lib\screens\write_log_page.dart', 'write'),
    (r'C:\dbros_app\lib\screens\log_list_page.dart', 'log')
  ];

  for (final item in files) {
    final path = item.$1;
    final kind = item.$2;
    final file = File(path);
    if (!file.existsSync()) continue;
    
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

    if (kind == 'write') {
        content = content.replaceAll("      beforeFocus: (target) async {", onFinishSkip + "      beforeFocus: (target) async {");
        content = content.replaceAll('OCR(자동 인식)', '콜카드 인식(자동 입력)');
        content = content.replaceAll('OCR(자동 인식) 이용 안내', '콜카드 인식(자동 입력) 이용 안내');
        content = content.replaceAll('OCR 기능은', '콜카드 인식 기능은');
        content = content.replaceAll('콜카드 이미지 자동 인식', '콜카드 인식(자동 입력)');
    }
        
    if (kind == 'log') {
        content = content.replaceAll("      opacityShadow: 0.8,\n    ).show(context: context);", "      opacityShadow: 0.8,\n" + onFinishSkip + "    ).show(context: context);");
    }

    file.writeAsStringSync(content);
    print('Updated ' + path);
  }
}

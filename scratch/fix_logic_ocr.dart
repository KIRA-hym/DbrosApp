import 'dart:io';

void main() {
  final writeLog = File(r'C:\dbros_app\lib\screens\write_log_page.dart');
  var wContent = writeLog.readAsStringSync();
  
  final wTargetFinish = '''
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
  wContent = wContent.replaceAll(wTargetFinish, replaceFinish);
  wContent = wContent.replaceAll(wTargetFinish.replaceAll('onFinish', 'onSkip'), replaceFinish.replaceAll('onFinish', 'onSkip'));
  
  // OCR terms
  wContent = wContent.replaceAll('OCR(자동 인식)', '콜카드 인식(자동 입력)');
  wContent = wContent.replaceAll('OCR(자동 인식) 이용 안내', '콜카드 인식(자동 입력) 이용 안내');
  wContent = wContent.replaceAll('OCR 기능은', '콜카드 인식 기능은');
  wContent = wContent.replaceAll('콜카드 이미지 자동 인식', '콜카드 인식(자동 입력)');
  writeLog.writeAsStringSync(wContent);

  final logList = File(r'C:\dbros_app\lib\screens\log_list_page.dart');
  var lContent = logList.readAsStringSync();
  final regexFinish = RegExp(r'onFinish:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\}');
  final regexSkip = RegExp(r'onSkip:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\}');
  lContent = lContent.replaceAll(regexFinish, replaceFinish.trim());
  lContent = lContent.replaceAll(regexSkip, replaceFinish.replaceAll('onFinish', 'onSkip').trim());
  logList.writeAsStringSync(lContent);
}

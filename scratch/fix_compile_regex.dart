import 'dart:io';

void main() {
  final writeLog = File(r'C:\dbros_app\lib\screens\write_log_page.dart');
  var content = writeLog.readAsStringSync();
  
  // 1. Fix the compile error with AppGlassDialog
  final regex = RegExp(r'bool\?\s*accepted\s*=\s*await\s*AppGlassDialog\.show<bool>\(\s*context:\s*context,\s*title:[\s\S]*?cancelText:\s*"[^"]+",\s*\);');
  
  final newDialog = '''    bool? accepted = await AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        title: "콜카드 인식(자동 입력) 이용 안내",
        icon: Icons.info_outline,
        contentWidget: const Text(
          "콜카드 인식 기능은 콜카드 이미지를 읽어 문구를 자동 입력하는 기능입니다.\\n\\n"
          "100% 완벽하지 않을 수 있으며, 화면 화질이나 폰트 설정 등에 따라 간혹 잘못된 값이 입력될 수 있습니다.\\n\\n"
          "자동 입력된 금액과 출발/도착지 등이 올바른지 저장 전 반드시 한 번 더 확인해 주세요.",
          style: TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
        ),
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              label: "취소",
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              label: "동의 및 계속",
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ),
        ],
      )
    );''';
  
  content = content.replaceFirst(regex, newDialog);
  
  // 2. Add onFinish and onSkip
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
  content = content.replaceAll("      beforeFocus: (target) async {", onFinishSkip + "      beforeFocus: (target) async {");
  
  // 3. Update OCR terms everywhere else
  content = content.replaceAll('OCR(자동 인식)', '콜카드 인식(자동 입력)');
  content = content.replaceAll('OCR(자동 인식) 이용 안내', '콜카드 인식(자동 입력) 이용 안내');
  content = content.replaceAll('OCR 기능은', '콜카드 인식 기능은');
  content = content.replaceAll('콜카드 이미지 자동 인식', '콜카드 인식(자동 입력)');
  
  writeLog.writeAsStringSync(content);
  print('Updated write_log_page.dart');
}

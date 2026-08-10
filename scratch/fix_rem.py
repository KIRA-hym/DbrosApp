import os
import re

files = [
    (r'C:\dbros_app\lib\screens\write_log_page.dart', 'write'),
    (r'C:\dbros_app\lib\screens\log_list_page.dart', 'log')
]

for path, kind in files:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    on_finish_skip = """      onFinish: () {
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
"""
    if kind == 'write':
        # Add beforeFocus
        content = content.replace("      beforeFocus: (target) async {", on_finish_skip + "      beforeFocus: (target) async {")
        
        # Replace OCR terms
        content = content.replace('OCR(자동 인식)', '콜카드 인식(자동 입력)')
        content = content.replace('OCR(자동 인식) 이용 안내', '콜카드 인식(자동 입력) 이용 안내')
        content = content.replace('OCR 기능은', '콜카드 인식 기능은')
        content = content.replace('콜카드 이미지 자동 인식', '콜카드 인식(자동 입력)')
        
    if kind == 'log':
        # Replace ).show(context: context); for TutorialCoachMark
        content = content.replace("      opacityShadow: 0.8,\n    ).show(context: context);", "      opacityShadow: 0.8,\n" + on_finish_skip + "    ).show(context: context);")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Updated ' + path)

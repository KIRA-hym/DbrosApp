import sys
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    content = re.sub(r'(keyTarget: _key[^,]+,)\s*color: Colors\.black,', r'\1\n          alignSkip: Alignment.bottomRight,\n          color: Colors.black,', content)
    content = re.sub(r'align:\s*ContentAlign\.(bottom|top),', r'align: ContentAlign.custom,\n              customPosition: CustomTargetContentPosition(top: 0),', content)

    if 'TutorialCoachMark(' in content and 'onFinish:' not in content:
        nav_code = '''      opacityShadow: 0.8,
      onFinish: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          try { Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst); } catch (_) {}
          mainTabEventController.add(4);
        });
        return true;
      },
      onSkip: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          try { Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst); } catch (_) {}
          mainTabEventController.add(4);
        });
        return true;
      },'''
        content = content.replace('opacityShadow: 0.8,', nav_code)
        
        if 'main_navigation.dart' not in content:
            content = content.replace("import '../main.dart';", "import '../main.dart';\nimport '../main_navigation.dart';")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

process_file('C:/dbros_app/lib/screens/write_log_page.dart')
process_file('C:/dbros_app/lib/screens/log_list_page.dart')
print('Done!')

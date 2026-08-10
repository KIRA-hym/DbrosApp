import os
import re

files = [
    r'C:\dbros_app\lib\screens\home_page.dart',
    r'C:\dbros_app\lib\screens\log_list_page.dart',
    r'C:\dbros_app\lib\screens\stats_page.dart',
    r'C:\dbros_app\lib\screens\settings_page.dart',
    r'C:\dbros_app\lib\screens\write_log_page.dart',
]

for path in files:
    if not os.path.exists(path): continue
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Update TargetFocus alignSkip
    # We find TargetFocus( ... contents: [ and inject alignSkip if missing, or replace it.
    # It's safer to just replace any alignSkip: Alignment.xxx, with alignSkip: Alignment.bottomRight,
    # and if it doesn't exist, we add it.
    
    def replace_target_focus(m):
        block = m.group(0)
        # remove existing alignSkip
        block = re.sub(r'\s*alignSkip:\s*Alignment\.[a-zA-Z]+,', '', block)
        # inject before contents:
        block = re.sub(r'(\s*)(contents:\s*\[)', r'\1alignSkip: Alignment.bottomRight,\1\2', block)
        return block
        
    content = re.sub(r'TargetFocus\([^\[]+contents:\s*\[', replace_target_focus, content, flags=re.DOTALL)
    
    # 2. Update TargetContent alignment
    def replace_target_content(m):
        block = m.group(0)
        block = re.sub(r'\s*align:\s*ContentAlign\.[a-zA-Z]+,', '', block)
        block = re.sub(r'\s*customPosition:\s*CustomTargetContentPosition\([^\)]*\),?', '', block)
        block = re.sub(r'(\s*)(builder:\s*\([^\)]+\)\s*\{)', r'\1align: ContentAlign.custom,\1customPosition: CustomTargetContentPosition(top: 0),\1\2', block)
        return block

    content = re.sub(r'TargetContent\([^\{]+builder:\s*\([^\)]+\)\s*\{', replace_target_content, content, flags=re.DOTALL)
    
    # 3. Add Onboarding logic to home_page.dart
    if 'home_page.dart' in path:
        old_init = '''    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PermissionDisclosureDialog.showIfNeeded(context);'''
        new_init = '''    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await PermissionDisclosureDialog.showIfNeeded(context);
        if (mounted) {
          await OnboardingDialog.showIfNeeded(context);
        }'''
        content = content.replace(old_init, new_init)
        
        # Add import
        if 'import \'../widgets/onboarding_dialog.dart\';' not in content:
            content = content.replace(
                "import '../widgets/permission_disclosure_dialog.dart';",
                "import '../widgets/permission_disclosure_dialog.dart';\nimport '../widgets/onboarding_dialog.dart';"
            )

    # 4. Fix nav logic for write_log_page and log_list_page
    replaceFinish = '''        onFinish: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
            mainTabEventController.add(4);
          });
          return true;
        },'''
    replaceSkip = replaceFinish.replace('onFinish', 'onSkip')

    if 'write_log_page.dart' in path:
        targetFinish = '''        onFinish: () {
          final route = ModalRoute.of(context);
          final isPushed = route != null && !route.isFirst;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isPushed && route.isActive) {
              Navigator.of(context, rootNavigator: true).removeRoute(route);
            }
            mainTabEventController.add(4);
          });
          return true;
        },'''
        content = content.replace(targetFinish, replaceFinish)
        content = content.replace(targetFinish.replace('onFinish', 'onSkip'), replaceSkip)
        
        oldFinish1 = '''        onFinish: () {
          final nav = Navigator.of(context, rootNavigator: true);
          final canPop = nav.canPop();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (canPop) {
              nav.pop();
            }
            mainTabEventController.add(4);
          });
          return true;
        },'''
        content = content.replace(oldFinish1, replaceFinish)
        content = content.replace(oldFinish1.replace('onFinish', 'onSkip'), replaceSkip)
        
        # Update OCR terms
        content = content.replace('OCR(자동 인식)', '콜카드 인식(자동 입력)')
        content = content.replace('OCR(자동 인식) 이용 안내', '콜카드 인식(자동 입력) 이용 안내')
        content = content.replace('OCR 기능은', '콜카드 인식 기능은')
        content = content.replace('콜카드 이미지 자동 인식', '콜카드 인식(자동 입력)')
        
    if 'log_list_page.dart' in path:
        content = re.sub(r'onFinish:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\},?', replaceFinish, content)
        content = re.sub(r'onSkip:\s*\(\)\s*\{\s*if\s*\(mounted\)\s*mainTabEventController\.add\(4\);\s*return\s*true;\s*\},?', replaceSkip, content)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Updated ' + path)

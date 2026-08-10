import os
import re

files = [
    (r'C:\dbros_app\lib\screens\write_log_page.dart', 'write'),
    (r'C:\dbros_app\lib\screens\log_list_page.dart', 'log')
]

for path, kind in files:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    if kind == 'write':
        old_dialog = """    bool? accepted = await AppGlassDialog.show<bool>(
      context: context,
      title: "콜카드 인식(자동 입력) 이용 안내",
      icon: Icons.info_outline,
      contentWidget: const Text(
        "콜카드 인식 기능은 콜카드 이미지를 읽어 문구를 자동 입력하는 기능입니다.\\n\\n"
        "100% 완벽하지 않을 수 있으며, 화면 화질이나 폰트 설정 등에 따라 간혹 잘못된 값이 입력될 수 있습니다.\\n\\n"
        "자동 입력된 금액과 출발/도착지 등이 올바른지 저장 전 반드시 한 번 더 확인해 주세요.",
        style: TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
      ),
      confirmText: "동의 및 계속",
      cancelText: "취소",
    );"""
        new_dialog = """    bool? accepted = await AppGlassDialog.show<bool>(
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
    );"""
        content = content.replace(old_dialog, new_dialog)

    if kind == 'log':
        if "import '../main_navigation.dart';" not in content:
            content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../main_navigation.dart';")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Updated ' + path)

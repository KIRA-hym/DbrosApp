import 'dart:io';

void main() {
  final homePath = r'C:\dbros_app\lib\screens\home_page.dart';
  final statsPath = r'C:\dbros_app\lib\screens\stats_page.dart';
  final settingsPath = r'C:\dbros_app\lib\screens\settings_page.dart';

  // 1. home_page.dart
  var homeContent = File(homePath).readAsStringSync();
  if (!homeContent.contains("import '../main_navigation.dart';")) {
    homeContent = homeContent.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../main_navigation.dart';");
  }
  final homeOnFinishSkip = '''      onFinish: () {
        if (mounted) mainTabEventController.add(4);
        return true;
      },
      onSkip: () {
        if (mounted) mainTabEventController.add(4);
        return true;
      },
''';
  if (!homeContent.contains('onFinish: ()')) {
    homeContent = homeContent.replaceFirst("      opacityShadow: 0.8,\n    )..show(context: context);", "      opacityShadow: 0.8,\n$homeOnFinishSkip    )..show(context: context);");
    File(homePath).writeAsStringSync(homeContent);
    print('Updated home_page.dart');
  }

  // 2. stats_page.dart
  var statsContent = File(statsPath).readAsStringSync();
  if (!statsContent.contains("import '../main_navigation.dart';")) {
    statsContent = statsContent.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../main_navigation.dart';");
  }
  if (!statsContent.contains('onFinish: ()')) {
    statsContent = statsContent.replaceFirst("      beforeFocus: (target) async {", "$homeOnFinishSkip      beforeFocus: (target) async {");
    File(statsPath).writeAsStringSync(statsContent);
    print('Updated stats_page.dart');
  }

  // 3. settings_page.dart
  var settingsContent = File(settingsPath).readAsStringSync();
  if (!settingsContent.contains('final ScrollController _scrollController')) {
    settingsContent = settingsContent.replaceFirst("class _SettingsPageState extends State<SettingsPage> {\n", "class _SettingsPageState extends State<SettingsPage> {\n  final ScrollController _scrollController = ScrollController();\n");
    settingsContent = settingsContent.replaceFirst("  void dispose() {\n", "  void dispose() {\n    _scrollController.dispose();\n");
    // There are multiple SingleChildScrollView, but the main one has padding: EdgeInsets.all(horizontalPadding)
    settingsContent = settingsContent.replaceAll("return SingleChildScrollView(\n", "return SingleChildScrollView(\n        controller: _scrollController,\n");
    
    final settingsOnFinishSkip = '''      onFinish: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
        return true;
      },
      onSkip: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
        return true;
      },
''';
    settingsContent = settingsContent.replaceFirst("      beforeFocus: (target) async {", "$settingsOnFinishSkip      beforeFocus: (target) async {");
    File(settingsPath).writeAsStringSync(settingsContent);
    print('Updated settings_page.dart');
  }
}

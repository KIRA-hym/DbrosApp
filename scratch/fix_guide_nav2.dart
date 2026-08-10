import 'dart:io';
void main() {
  final homePath = r'C:\dbros_app\lib\screens\home_page.dart';
  final statsPath = r'C:\dbros_app\lib\screens\stats_page.dart';

  final onFinishSkip = '''      onFinish: () {
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
      },
''';

  // 1. home_page.dart
  var home = File(homePath).readAsStringSync();
  if (!home.contains('onFinish: ()')) {
    home = home.replaceAll(RegExp(r'opacityShadow:\s*0\.8,\s*\)\.\.show\(context:\s*context\);'), 'opacityShadow: 0.8,\n$onFinishSkip    )..show(context: context);');
  } else {
    // If it already has onFinish, replace it entirely
    home = home.replaceAll(RegExp(r'onFinish:\s*\(\)\s*\{[\s\S]*?return\s+true;\s*\},[\s\S]*?onSkip:\s*\(\)\s*\{[\s\S]*?return\s+true;\s*\},'), onFinishSkip);
  }
  File(homePath).writeAsStringSync(home);
  print('home fixed');

  // 2. stats_page.dart
  var stats = File(statsPath).readAsStringSync();
  if (stats.contains('onFinish: ()')) {
    stats = stats.replaceAll(RegExp(r'onFinish:\s*\(\)\s*\{[\s\S]*?return\s+true;\s*\},[\s\S]*?onSkip:\s*\(\)\s*\{[\s\S]*?return\s+true;\s*\},'), onFinishSkip);
  }
  File(statsPath).writeAsStringSync(stats);
  print('stats fixed');
}

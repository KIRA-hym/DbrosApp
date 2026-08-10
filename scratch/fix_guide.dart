import 'dart:io';

void main() {
  processFile('C:/dbros_app/lib/screens/write_log_page.dart');
  processFile('C:/dbros_app/lib/screens/log_list_page.dart');
}

void processFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync();

  // Add alignSkip if not present and color is black
  content = content.replaceAllMapped(RegExp(r'(keyTarget:\s*_key[^,]+,)\s*color:\s*Colors\.black,'), (match) {
    return '${match.group(1)}\n          alignSkip: Alignment.bottomRight,\n          color: Colors.black,';
  });

  // Replace ContentAlign
  content = content.replaceAll(RegExp(r'align:\s*ContentAlign\.(bottom|top),'), 'align: ContentAlign.custom,\n              customPosition: CustomTargetContentPosition(top: 0),');

  // Add onFinish and onSkip to write_log_page TutorialCoachMark
  if (path.contains('write_log_page') && content.contains('TutorialCoachMark(') && !content.contains('onFinish:')) {
    final navCode = '''      opacityShadow: 0.8,
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
      },''';
    content = content.replaceFirst('opacityShadow: 0.8,', navCode);

    if (!content.contains('main_navigation.dart')) {
      content = content.replaceFirst("import '../main.dart';", "import '../main.dart';\nimport '../main_navigation.dart';");
    }
  }

  file.writeAsStringSync(content);
}

import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('lib/screens/home_page.dart');
  if (!file.existsSync()) return;
  var content = file.readAsStringSync(encoding: utf8);

  // Revert the placeholder back to scaffoldBackgroundColor
  // The first replacement replaces the `_latestYoutubeVideoId == null` container
  content = content.replaceFirst(
    'child: _latestYoutubeVideoId == null\n                              ? Container(\n                                  color: Theme.of(context).cardTheme.color!,',
    'child: _latestYoutubeVideoId == null\n                              ? Container(\n                                  color: Theme.of(context).scaffoldBackgroundColor,'
  );

  // The second replacement replaces the `errorBuilder` container
  content = content.replaceFirst(
    'errorBuilder: (_, _, _) => Container(\n                                    color: Theme.of(context).cardTheme.color!,',
    'errorBuilder: (_, _, _) => Container(\n                                    color: Theme.of(context).scaffoldBackgroundColor,'
  );

  file.writeAsStringSync(content, encoding: utf8);
}

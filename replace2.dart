import 'dart:io';

void main() {
  final file = File('lib/screens/write_log_page.dart');
  String content = file.readAsStringSync();
  
  // Convert all to \n to make matching easier
  content = content.replaceAll('\r\n', '\n');

  final targetRegex = RegExp(r'''  Widget _buildLocationInputField\(\n    TextEditingController controller, \{\n    required String label,\n    double bottomMargin = 16,\n    FocusNode\? focusNode,\n    Widget\? suffixIcon,\n    bool isError = false,\n  \}\) \{\n    return Column\(\n      crossAxisAlignment: CrossAxisAlignment\.start,\n      children: \[\n        Text\(\n          label,\n          style: Theme\.of\(context\)\.textTheme\.bodySmall\?\.copyWith\(\n            color:\n                \(Theme\.of\(context\)\.textTheme\.bodySmall\?\.color \?\? Colors\.grey\),\n          \),\n        \),''');

  final replacement = '''  Widget _buildLocationInputField(
    TextEditingController controller, {
    required String label,
    double bottomMargin = 16,
    FocusNode? focusNode,
    Widget? suffixIcon,
    bool isError = false,
    Widget? labelAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                ),
              ),
            ),
            if (labelAction != null) ...[
              SizedBox(width: 8),
              labelAction,
            ],
          ],
        ),''';

  if (targetRegex.hasMatch(content)) {
    content = content.replaceFirst(targetRegex, replacement);
    file.writeAsStringSync(content);
    print('Replaced successfully.');
  } else {
    print('Pattern not found.');
  }
}

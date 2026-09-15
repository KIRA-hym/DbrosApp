import 'dart:io';

void main() {
  final file = File('lib/screens/write_log_page.dart');
  String content = file.readAsStringSync();
  
  final target = '''  Widget _buildLocationInputField(
    TextEditingController controller, {
    required String label,
    double bottomMargin = 16,
    FocusNode? focusNode,
    Widget? suffixIcon,
    bool isError = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color:
                (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
          ),
        ),''';
        
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

  content = content.replaceAll(target, replacement);
  
  // also normalize newlines just in case
  content = content.replaceAll('\r\n', '\n');
  
  file.writeAsStringSync(content);
  print('Done.');
}

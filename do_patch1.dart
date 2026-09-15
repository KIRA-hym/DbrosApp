import 'dart:io';

void main() {
  var file = File('lib/screens/write_log_page.dart');
  var content = file.readAsStringSync();
  
  // Find Text wrapped in Expanded
  final regex = RegExp(r'Expanded\(\s*child: Text\(\s*label,\s*style: Theme\.of\(context\)\.textTheme\.bodySmall\?\.copyWith\(\s*color:\s*\(Theme\.of\(context\)\.textTheme\.bodySmall\?\.color \?\? Colors\.grey\),\s*\),\s*\),\s*\),');
  
  if (regex.hasMatch(content)) {
    content = content.replaceFirst(regex, '''Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                  ),
                ),''');
    
    // now find the place to insert Spacer()
    final rowRegex = RegExp(r'if \(labelAction != null\) \.\.\.\[\s*SizedBox\(width: 8\),\s*labelAction,\s*\],\s*\],\s*\),');
    content = content.replaceFirst(rowRegex, '''if (labelAction != null) ...[
                const SizedBox(width: 8),
                labelAction,
              ],
              const Spacer(),
            ],
          ),''');
          
    file.writeAsStringSync(content);
    print('Row replaced.');
  } else {
    print('Regex 1 not matched.');
  }
}

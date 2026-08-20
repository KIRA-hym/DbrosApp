
import "dart:io";

void main() {
  final file = File("lib/screens/write_log_page.dart");
  var content = file.readAsStringSync();
  
  final startStr = "optionsBuilder: (TextEditingValue v) async {";
  final endStr = "fieldViewBuilder: (context, con, fn, onFieldSubmitted) {";
  
  final startIdx = content.indexOf(startStr);
  final endIdx = content.indexOf(endStr);
  
  if (startIdx != -1 && endIdx != -1) {
    final replacement = """
optionsBuilder: (TextEditingValue v) async {
          if (v.text.isEmpty) return const Iterable<String>.empty();
          
          final query = v.text.trim();
          final queryLower = query.toLowerCase();
          final mode = SettingsService.addressSearchMode;
          
          List<String> historyMatches = [];
          Set<String> historySet = {};
          if (mode == 'both' || mode == 'history') {
            final historyRaw = _distinctLocations
                .where((s) => s.toLowerCase().contains(queryLower))
                .toList();
            historyMatches = historyRaw.map((s) => '[최근] \$s').toList();
            historySet = historyRaw.toSet();
          }
          
          List<String> filteredDbMatches = [];
          if (mode == 'both' || mode == 'address') {
            final dbMatches = await AddressRepository().search(query);
            filteredDbMatches = dbMatches.where((s) => !historySet.contains(s)).toList();
          }
          
          return [...historyMatches, ...filteredDbMatches];
        },
        """;
        
    content = content.replaceRange(startIdx, endIdx, replacement);
    file.writeAsStringSync(content);
    print("Success write_log_page.dart");
  } else {
    print("Failed to find target in write_log_page.dart");
  }
}

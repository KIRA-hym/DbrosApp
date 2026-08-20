
import "dart:io";

void main() {
  final file = File("lib/ui/overlay/quick_entry_popup_form.dart");
  var content = file.readAsStringSync();
  
  final startStr = "Future<void> _searchOrigin(String query) async {";
  final endStr = "Future<void> _submit() async {";
  
  final startIdx = content.indexOf(startStr);
  final endIdx = content.indexOf(endStr);
  
  if (startIdx != -1 && endIdx != -1) {
    final replacement = """
Future<void> _searchOrigin(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() => _originSuggestions = []);
      return;
    }
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
    
    if (mounted) setState(() => _originSuggestions = [...historyMatches, ...filteredDbMatches]);
  }

  Future<void> _searchDest(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() => _destSuggestions = []);
      return;
    }
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
    
    if (mounted) setState(() => _destSuggestions = [...historyMatches, ...filteredDbMatches]);
  }

  """;
        
    content = content.replaceRange(startIdx, endIdx, replacement);
    file.writeAsStringSync(content);
    print("Success quick_entry_popup_form.dart");
  } else {
    print("Failed to find target in quick_entry_popup_form.dart");
  }
}

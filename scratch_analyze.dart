import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('D:\\DbrosApp\\logs\\ocr_parse_export_20260517.json');
  final str = await file.readAsString();
  final data = jsonDecode(str);
  final entries = data['entries'] as List;
  
  final badParses = {
    '로지': [],
    '콜마너': [],
    '카카오(일반)': [],
  };

  for (final e in entries) {
    final prog = e['program'] ?? '';
    final parsed = e['parsed_data'] ?? {};
    final dep = parsed['departure']?.toString() ?? '';
    final dest = parsed['destination']?.toString() ?? '';
    
    bool isBad = false;
    if (dep.contains('지도') || dep.contains('취소') || dep.contains('갱신') || dep.length > 40) isBad = true;
    if (dest.contains('지도') || dest.contains('취소') || dest.contains('갱신') || dest.length > 40) isBad = true;
    
    if (isBad && badParses.containsKey(prog) && badParses[prog]!.length < 5) {
      badParses[prog]!.add(e);
    }
  }

  print('Analysis Complete.');
  for (final p in badParses.keys) {
    print('\\n--- $p Bad Parses ---');
    for (final x in badParses[p]!) {
      print('ID: ${x['id']}');
      print('Parsed Dep: ${x['parsed_data']['departure']}');
      print('Parsed Dest: ${x['parsed_data']['destination']}');
    }
  }
}

import 'dart:io';

void main() {
  var file = File('lib/utils/logi_colmanner_ocr.dart');
  var text = file.readAsStringSync();
  
  final origBlacklist = "final blacklist = ['특이사항', '서명', '도착지', '출발지', '력', '갱신', '닫기', '지도'];";
  final newBlacklist = "final blacklist = ['특이사항', '서명', '도착지', '출발지', '력', '갱신', '닫기'];\n      res = res.replaceAll(RegExp(r'\\s+지도\\s*\$'), '');";
  
  text = text.replaceFirst(origBlacklist, newBlacklist);
  file.writeAsStringSync(text);
}

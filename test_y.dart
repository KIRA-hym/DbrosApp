import 'package:dbros_app/utils/logi_fare_parse.dart';
void main() {
  String raw = '155 000 31000 12000';
  var cleanedRaw = raw.replaceAll(RegExp(r'\d{9,15}'), '');
  String s = cleanedRaw.replaceAll(',', '').replaceAll('.', '').replaceAll(RegExp(r'\s'), '');
  s = s.replaceAll(RegExp(r'[12]!+$'), '');
  s = s.replaceAll(RegExp(r'원|₩|P'), '');
  s = s.replaceAll(RegExp(r'[!]+'), '');
  print(s);
  var matches = RegExp(r'\d{4,6}').allMatches(s);
  var candidates = matches.map((m) => m.group(0)!).toList()..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
  print(candidates);
}

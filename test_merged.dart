import 'package:dbros_app/utils/logi_fare_parse.dart';
void main() {
  var s = '1550003100012000';
  print(RegExp(r'\d{4,6}').allMatches(s).map((m) => m.group(0)).toList());
}

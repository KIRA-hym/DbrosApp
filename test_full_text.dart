import 'package:dbros_app/utils/logi_fare_parse.dart';
void main() {
  print(parseLogiFareFromOcrText('요금\n92201505137\n155\n000\n31000\n법인'.replaceAll('\n', ' ')));
}

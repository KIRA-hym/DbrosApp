import 'package:dbros_app/utils/logi_fare_parse.dart';
void main() {
  print('Test 1: ' + parseLogiFareFromOcrText('92201505137 155000').toString());
  print('Test 2: ' + parseLogiFareFromOcrText('155.000').toString());
  print('Test 3: ' + parseLogiFareFromOcrText('¿ä±Ý 155000').toString());
  print('Test 4: ' + parseLogiFareFromOcrText('155000 31000').toString());
}

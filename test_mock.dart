import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
void main() {
  final lines = ['요금', '입금액', '고객', '메모', '92201505137 155000', '31000', '법인'];
  print(LogiColmannerOcr.getGrossFareFromLogiFareDepositStackForTest(lines));
}

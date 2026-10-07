import 'package:dbros_app/utils/logi_colmanner_ocr.dart';
import 'package:dbros_app/utils/logi_fare_parse.dart';

void main() {
  final lines = [
    '요금',
    '입금액',
    '고객',
    '메모',
    '적요',
    '전화',
    '전화2',
    '출발지',
    '도착지',
    '경로',
    '안내',
    '&하나로(주)HnH 하나로',
    '92201505137',
    '155000',
    '31000'
  ];
  
  var inSection = false;
  final amounts = <int>[];
  for (final trimmed in lines) {
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('요금') || trimmed.startsWith('입금액')) {
      inSection = true;
      final inline = parseLogiFareFromOcrText(trimmed);
      if (inline != null && inline >= 1000) amounts.add(inline);
      continue;
    }
    if (!inSection) continue;
    if (RegExp(r'\\d{9,}').hasMatch(trimmed)) continue;

    final fromOcr = parseLogiFareFromOcrText(trimmed);
    print('trimmed: \$trimmed, fromOcr: \$fromOcr');
    
    // Simulate _strictFareDigitsFromLine
    int? v = fromOcr;
    if (v == null) {
      var t = trimmed.trim().replaceAll(',', '').replaceAll(RegExp(r'\\s'), '');
      t = t.replaceAll(RegExp(r'[!]+'), '').replaceAll(RegExp(r'[원₩lL|I]+'), '');
      if (RegExp(r'^\\d{4,6}\$').hasMatch(t)) {
        v = normalizeLogiFareDigitToken(t);
        if (v != null && v > 500000) v = null;
      }
    }
    
    print('trimmed: \$trimmed, v: \$v');
    if (v != null && v >= 1000 && v <= 999999 && !amounts.contains(v)) {
      amounts.add(v);
    }
  }
  print('amounts: \$amounts');
}

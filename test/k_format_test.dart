import 'package:flutter_test/flutter_test.dart';

String _formatToKValue(int amount) {
  if (amount <= 0) return '';
  if (amount % 1000 == 0) {
    return '${amount ~/ 1000}k';
  } else {
    final double kValue = amount / 1000;
    return '${kValue.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), "")}k';
  }
}

void main() {
  test('k format conversion tests', () {
    expect(_formatToKValue(3000), '3k');
    expect(_formatToKValue(15000), '15k');
    expect(_formatToKValue(3500), '3.5k');
    expect(_formatToKValue(15400), '15.4k');
    expect(_formatToKValue(0), '');
    expect(_formatToKValue(-100), '');
  });
}

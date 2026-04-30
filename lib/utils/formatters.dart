import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final TextInputFormatter thousandSeparatorFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
  final String numbersOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
  if (numbersOnly.isEmpty) return const TextEditingValue(text: '');
  
  final String formatted = NumberFormat('#,###').format(int.parse(numbersOnly));
  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: formatted.length),
  );
});
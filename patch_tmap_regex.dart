import 'dart:io';

void main() {
  final file = File('lib/utils/tmap_trip_detail_ocr.dart');
  var text = file.readAsStringSync();

  final targetStart = '    // --- NEW FALLBACK FOR VERTICAL/TWO-COLUMN FORMAT ---';
  final targetEnd = '    // ---------------------------------------------------';

  final startIndex = text.indexOf(targetStart);
  final endIndex = text.indexOf(targetEnd);
  
  if (startIndex == -1 || endIndex == -1) {
    print('Target strings not found');
    return;
  }

  final before = text.substring(0, startIndex);
  final after = text.substring(endIndex + targetEnd.length);

  final newFallback = '''    // --- ROBUST FALLBACK FOR ADDRESSES USING REGEX ---
    if (startAddress.isEmpty || endAddress.isEmpty) {
      final flat2 = normalized.replaceAll(RegExp(r'\\s+'), ' ');
      final addrRegex = RegExp(r'(\\uC11C\\uC6B8|\\uBD80\\uC0B0|\\uB300\\uAD6C|\\uC778\\uCC9C|\\uAD11\\uC8FC|\\uB300\\uC804|\\uC6B8\\uC0B0|\\uC138\\uC885|\\uACBD\\uAE30|\\uAC15\\uC6D0|\\uCDA9\\uBD81|\\uCDA9\\uB0A8|\\uC804\\uBD81|\\uC804\\uB0A8|\\uACBD\\uBD81|\\uACBD\\uB0A8|\\uC81C\\uC8FC)\\s+[\\uAC00-\\uD7A3]+\\s*(?:\\uC2DC|\\uAD70|\\uAD6C)\\s+[^\\uB3C4\\uCC29\\uC2E4\\uC218\\uC775\\n]*');
      final matches = addrRegex.allMatches(flat2).toList();
      
      if (matches.isNotEmpty) {
        if (startAddress.isEmpty) startAddress = matches.first.group(0)!.trim();
        if (endAddress.isEmpty) endAddress = matches.last.group(0)!.trim();
      }
    }

    if (grossFare == 0) {
      final fareMatch = RegExp(r'([\\d,]+)\\s*P').firstMatch(normalized.replaceAll(RegExp(r'\\s+'), ' '));
      if (fareMatch != null) {
        grossFare = int.tryParse(fareMatch.group(1)!.replaceAll(',', '')) ?? 0;
      }
    }
    // ---------------------------------------------------''';

  final newText = before + newFallback + after;
  file.writeAsStringSync(newText);
  print('Replaced successfully');
}
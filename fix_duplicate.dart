import 'dart:io';

void main() {
  final file = File('lib/utils/tmap_trip_detail_ocr.dart');
  var text = file.readAsStringSync();

  final badText = '''    // ---------------------------------------------------

    if (grossFare == 0 && startAddress.isEmpty && endAddress.isEmpty) {
    // ---------------------------------------------------

    if (grossFare == 0 && startAddress.isEmpty && endAddress.isEmpty) {
      return null;
    }''';

  final goodText = '''    // ---------------------------------------------------

    if (grossFare == 0 && startAddress.isEmpty && endAddress.isEmpty) {
      return null;
    }''';

  text = text.replaceFirst(badText, goodText);
  file.writeAsStringSync(text);
}
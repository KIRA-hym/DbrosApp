import 'dart:io';

void main() {
  final file = File('lib/utils/tmap_trip_detail_ocr.dart');
  var text = file.readAsStringSync();

  // 1. Add cleanAddr logic before the empty checks
  final targetStr = "    if (startAddress.isEmpty || endAddress.isEmpty || grossFare == 0) {";
  final cleanLogic = '''    // Cleanup garbage appended by ML Kit grouping
    String cleanAddr(String a) {
      if (a.isEmpty) return a;
      var res = a;
      final fareMatch = RegExp(r'\\d{1,3}(,\\d{3})*\\s*[P원]').firstMatch(res);
      if (fareMatch != null) res = res.substring(0, fareMatch.start);
      final insIdx = res.indexOf('보험');
      if (insIdx != -1) res = res.substring(0, insIdx);
      return res.trim();
    }
    startAddress = cleanAddr(startAddress);
    endAddress = cleanAddr(endAddress);

    if (startAddress.isEmpty || endAddress.isEmpty || grossFare == 0) {''';
  text = text.replaceFirst(targetStr, cleanLogic);

  // 2. Fix the Date regex
  final oldRegex = r"RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~')";
  final newRegex = r"RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})')";
  text = text.replaceFirst(oldRegex, newRegex);

  file.writeAsStringSync(text);
}
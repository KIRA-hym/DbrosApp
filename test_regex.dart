void main() {
  String text1 = "款青老磊 2026.8.29 (配) 00:50 ~ 01:35";
  String text2 = "款青老磊\n2026.8.29 (配)\n00:50 ~ 01:35";
  
  void parse(String input) {
    final flat = input.replaceAll(RegExp(r'\s+'), ' ');
    final flatMatch = RegExp(r'款青老磊\s*(\d{4})[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~').firstMatch(flat);
    if (flatMatch != null) {
      final y = flatMatch.group(1)!;
      final m = flatMatch.group(2)!.padLeft(2, '0');
      final d = flatMatch.group(3)!.padLeft(2, '0');
      print('Date: $y-$m-$d, Time: ${flatMatch.group(4)}');
    } else {
      print('Failed');
    }
  }
  
  parse(text1);
  parse(text2);
}

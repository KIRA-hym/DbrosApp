void main() {
  String flat = '款青老磊 2026.8.29 (配) 00:50 ~ 01:35';
  final dtMatch = RegExp(r'款青老磊\s*(\d{4})[.\-](\d{1,2})[.\-](\d{1,2}).*?(\d{2}:\d{2})\s*~').firstMatch(flat);
  if (dtMatch != null) {
      final y = dtMatch.group(1)!;
      final m = dtMatch.group(2)!.padLeft(2, '0');
      final d = dtMatch.group(3)!.padLeft(2, '0');
      print('Date: $y-$m-$d, Time: ${dtMatch.group(4)}');
  } else {
      print('Failed date regex');
  }
}

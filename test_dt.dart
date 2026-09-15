void main() {
  String flat = '11:52 D \uC6B4\uD589\uBC88\uD638 42443611 \uCD9C\uBC1C \uC6B4\uD589\uC77C\uC790 2026.8.29 (\uD1A0) 00:50 ~ 01:35';
  final dtMatch = RegExp(r'\uC6B4\uD589\uC77C\uC790\s*(\d{4})\s*[.\-\uB144]\s*(\d{1,2})\s*[.\-\uC6D4]\s*(\d{1,2}).*?(\d{2}\s*:\s*\d{2})\s*~').firstMatch(flat);
  if (dtMatch != null) {
      print('Matched: ' + dtMatch.group(1)! + '-' + dtMatch.group(2)! + '-' + dtMatch.group(3)!);
  } else {
      print('FAILED');
  }
}
void main() {
  print(RegExp(r'^[가-힣]{2,6}동\s*\d*\s*가?[\s\)]').hasMatch('금호동3가)금호동금호두산AI04동'));
}

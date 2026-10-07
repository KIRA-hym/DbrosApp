void main() { print(RegExp(r'\d{4,6}').allMatches('15500031000').map((m) => m.group(0)!).toList()); }

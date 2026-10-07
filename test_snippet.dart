void main() {
  int? v = 155000;
  List<int> amounts = [];
  
  if (v != null) print('BOOL: \${v >= 1000} \${v <= 999999} \${!amounts.contains(v)}');
  if (v != null && v >= 1000 && v <= 999_999 && !amounts.contains(v)) {
    print('ADDING TO AMOUNTS: ' + v.toString()); amounts.add(v);
  }
}

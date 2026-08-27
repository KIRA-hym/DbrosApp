import 'dart:io'; import 'dart:convert'; void main() { print(jsonDecode(File('assets/data/common_points.json').readAsStringSync()).length); }

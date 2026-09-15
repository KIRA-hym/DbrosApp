import 'dart:io'; void main() { var f = File('pubspec.yaml'); var c = f.readAsStringSync(); f.writeAsStringSync(c); print('done'); }

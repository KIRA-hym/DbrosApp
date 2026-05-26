import 'dart:io';

void main() async {
  final file = File('test.zip');
  await file.writeAsBytes([80, 75, 3, 4, 10, 20]);
  
  final stream = file.openRead(0, 4);
  final bytes = await stream.first;
  print('bytes length: ${bytes.length}');
  print('bytes: $bytes');
}

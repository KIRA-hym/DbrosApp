import 'dart:io';

void main() async {
  final file = File('test.zip');
  await file.writeAsBytes([80, 75, 3, 4, 10, 20]);
  
  final raf = await file.open(mode: FileMode.read);
  final bytes = await raf.read(4);
  await raf.close();
  
  print('raf bytes length: ${bytes.length}');
  print('raf bytes: $bytes');
}

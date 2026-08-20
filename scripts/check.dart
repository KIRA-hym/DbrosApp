import 'dart:io';
void main() {
  final lines = File('assets/road_names.txt').readAsLinesSync();
  for(int i=0; i<5; i++) {
    print(lines[i]);
  }
}

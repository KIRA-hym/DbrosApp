import 'dart:io';
import 'package:archive/archive.dart';

void main() {
  final bytes = File('build/app/outputs/bundle/release/app-release.aab').readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive) {
    if (file.name == 'base/manifest/AndroidManifest.xml') {
      final content = file.content as List<int>;
      // Basic text extraction from binary xml
      final str = String.fromCharCodes(content.where((c) => c >= 32 && c <= 126));
      print('Extracted string: \');
    }
  }
}

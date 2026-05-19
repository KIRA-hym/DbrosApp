import 'dart:io';
import 'file:///C:/Users/HYM/AppData/Local/Pub/Cache/hosted/pub.dev/image-4.8.0/lib/image.dart' as img;

void main() {
  print('=== Inspecting existing Android Resource Image Sizes ===');
  
  final resDir = Directory('android/app/src/main/res');
  if (!resDir.existsSync()) {
    print('Error: Resource directory not found!');
    return;
  }

  final subDirs = resDir.listSync();
  for (var entity in subDirs) {
    if (entity is Directory) {
      final dirName = entity.path.split(Platform.pathSeparator).last;
      if (dirName.startsWith('mipmap-') || dirName.startsWith('drawable-')) {
        inspectFile(entity, 'launcher_icon.png');
        inspectFile(entity, 'ic_launcher_foreground.png');
        inspectFile(entity, 'splash.png');
        inspectFile(entity, 'android12splash.png');
      }
    }
  }
}

void inspectFile(Directory dir, String filename) {
  final file = File('${dir.path}/$filename');
  if (file.existsSync()) {
    try {
      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image != null) {
        final folder = dir.path.split(Platform.pathSeparator).last;
        print('$folder/$filename : ${image.width}x${image.height}');
      }
    } catch (e) {
      print('Error reading ${dir.path}/$filename: $e');
    }
  }
}

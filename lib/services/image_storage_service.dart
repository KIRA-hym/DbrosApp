import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStorageService {
  static const int _maxLongEdge = 1280;
  static const int _jpegQuality = 78;

  static String _timestampId() => DateTime.now().microsecondsSinceEpoch.toString();

  static Future<Directory> _imagesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attached_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String?> compressAndPersistForDisplay(
    String? sourcePath, {
    String prefix = 'img',
  }) async {
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;
    final src = File(sourcePath);
    if (!await src.exists()) return null;

    final bytes = await src.readAsBytes();
    final decoded = img.decodeImage(bytes);
    final outDir = await _imagesDir();
    final outPath = p.join(outDir.path, '${prefix}_${_timestampId()}.jpg');
    final outFile = File(outPath);

    if (decoded == null) {
      await src.copy(outPath);
      return outPath;
    }

    img.Image target = decoded;
    final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longEdge > _maxLongEdge) {
      if (decoded.width >= decoded.height) {
        final newHeight = (decoded.height * (_maxLongEdge / decoded.width)).round();
        target = img.copyResize(decoded, width: _maxLongEdge, height: newHeight);
      } else {
        final newWidth = (decoded.width * (_maxLongEdge / decoded.height)).round();
        target = img.copyResize(decoded, width: newWidth, height: _maxLongEdge);
      }
    }

    final encoded = img.encodeJpg(target, quality: _jpegQuality);
    await outFile.writeAsBytes(encoded, flush: true);
    return outPath;
  }
}

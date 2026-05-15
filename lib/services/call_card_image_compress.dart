import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// 콜카드 이미지를 Gemini 전송용 JPEG로 리사이즈·압축한다.
abstract final class CallCardImageCompress {
  static const int _targetMaxBytes = 210000;
  static const int _longEdge1024 = 1024;
  static const int _longEdge800 = 800;

  /// 긴 축 1024→필요 시 800, 품질 78~60 루프로 용량 목표에 맞춘다.
  static Future<Uint8List> compressForGemini(String filePath) async {
    var longEdge = _longEdge1024;
    var quality = 78;
    Uint8List? best;
    for (var i = 0; i < 28; i++) {
      final out = await FlutterImageCompress.compressWithFile(
        filePath,
        minWidth: longEdge,
        minHeight: longEdge,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out == null || out.isEmpty) {
        throw StateError('이미지 압축 결과가 비었습니다.');
      }
      best = Uint8List.fromList(out);
      if (best.length <= _targetMaxBytes) return best;
      if (quality > 62) {
        quality -= 6;
        continue;
      }
      if (longEdge > _longEdge800) {
        longEdge = _longEdge800;
        quality = 76;
        continue;
      }
      return best;
    }
    if (best != null) return best;
    throw StateError('이미지 압축에 실패했습니다.');
  }
}

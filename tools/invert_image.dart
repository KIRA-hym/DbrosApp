import 'dart:io';
import 'package:image/image.dart';

void main() async {
  final inputPath = 'assets/title.png';
  final outputPath = 'assets/title_light.png';

  final bytes = await File(inputPath).readAsBytes();
  final img = decodeImage(bytes);

  if (img != null) {
    for (int y = 0; y < img.height; y++) {
      for (int x = 0; x < img.width; x++) {
        final pixel = img.getPixel(x, y);
        final a = pixel.a;

        // 투명하지 않은(로고가 그려진) 모든 픽셀을 완전한 검정색(0,0,0)으로 변경
        // a(투명도)는 원본을 유지하여 외곽선이 깨지지 않게 보존
        if (a > 0) {
          img.setPixelRgba(x, y, 0, 0, 0, a);
        }
      }
    }

    final outBytes = encodePng(img);
    await File(outputPath).writeAsBytes(outBytes);
    print('Successfully updated $outputPath (All non-transparent pixels to Black)');
  } else {
    print('Failed to decode image.');
  }
}

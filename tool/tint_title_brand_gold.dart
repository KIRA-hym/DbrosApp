// assets/title.png 를 앱 브랜드 골드 #FFC700 으로 직접 칠함 (알파 유지, UI ColorFiltered 없이 파일만 사용)
import 'dart:io';

import 'package:image/image.dart';

const _r = 0xFF;
const _g = 0xC7;
const _b = 0x00;

void main() {
  final root = Directory.current;
  final f = File('${root.path}/assets/title.png');
  if (!f.existsSync()) {
    stderr.writeln('assets/title.png not found');
    exitCode = 1;
    return;
  }
  final raw = f.readAsBytesSync();
  final img = decodeImage(raw);
  if (img == null) {
    stderr.writeln('decode failed');
    exitCode = 1;
    return;
  }

  File('${root.path}/assets/title_backup_before_brand_tint.png')
      .writeAsBytesSync(raw);

  for (var y = 0; y < img.height; y++) {
    for (var x = 0; x < img.width; x++) {
      final p = img.getPixel(x, y);
      final a = p.a.toInt();
      if (a < 8) continue;
      img.setPixelRgba(x, y, _r, _g, _b, a);
    }
  }

  f.writeAsBytesSync(encodePng(img));
  stdout.writeln('OK: assets/title.png → #FFC700 (백업: title_backup_before_brand_tint.png)');
}

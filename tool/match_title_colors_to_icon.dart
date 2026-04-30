// assets/title.png 로고 영역 색을 assets/icon.png 의 금색 톤 통계에 맞춤 (Reinhard Lab 이전)
// 흰색 등 저채도 텍스트 픽셀은 건드리지 않음.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart';

void main() {
  final root = Directory.current;
  final iconFile = File('${root.path}/assets/icon.png');
  final titleFile = File('${root.path}/assets/title.png');
  if (!iconFile.existsSync() || !titleFile.existsSync()) {
    stderr.writeln('assets/icon.png 및 assets/title.png 가 필요합니다.');
    exitCode = 1;
    return;
  }

  final iconBytes = iconFile.readAsBytesSync();
  final titleBytes = titleFile.readAsBytesSync();
  final iconDec = decodeImage(iconBytes);
  final titleDec = decodeImage(titleBytes);
  if (iconDec == null || titleDec == null) {
    stderr.writeln('PNG 디코딩 실패');
    exitCode = 1;
    return;
  }

  // 백업
  File('${root.path}/assets/title_backup_before_color_match.png').writeAsBytesSync(titleBytes);

  final iconLabs = <List<double>>[];
  for (var y = 0; y < iconDec.height; y++) {
    for (var x = 0; x < iconDec.width; x++) {
      final p = iconDec.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      if (_isBackgroundBlack(r, g, b)) continue;
      iconLabs.add(rgbToLab(r, g, b));
    }
  }
  if (iconLabs.isEmpty) {
    stderr.writeln('icon에서 전경 픽셀을 찾지 못했습니다.');
    exitCode = 1;
    return;
  }

  final titleLabsLogo = <List<double>>[];
  for (var y = 0; y < titleDec.height; y++) {
    for (var x = 0; x < titleDec.width; x++) {
      final p = titleDec.getPixel(x, y);
      if (p.a < 32) continue;
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      if (_skipWhiteOrGreyText(r, g, b)) continue;
      titleLabsLogo.add(rgbToLab(r, g, b));
    }
  }
  if (titleLabsLogo.isEmpty) {
    stderr.writeln('title에서 칠할 로고 픽셀이 없습니다.');
    exitCode = 1;
    return;
  }

  final iconMean = _meanLab(iconLabs);
  final iconStd = _stdLab(iconLabs, iconMean);
  final titleMean = _meanLab(titleLabsLogo);
  final titleStd = _stdLab(titleLabsLogo, titleMean);

  final eps = 1e-4;
  final out = titleDec.clone();

  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      if (p.a < 32) continue;
      final r0 = p.r.toInt(), g0 = p.g.toInt(), b0 = p.b.toInt();
      if (_skipWhiteOrGreyText(r0, g0, b0)) continue;

      final lab = rgbToLab(r0, g0, b0);
      final l2 = (lab[0] - titleMean[0]) * (iconStd[0] / math.max(titleStd[0], eps)) + iconMean[0];
      final a2 = (lab[1] - titleMean[1]) * (iconStd[1] / math.max(titleStd[1], eps)) + iconMean[1];
      final b2 = (lab[2] - titleMean[2]) * (iconStd[2] / math.max(titleStd[2], eps)) + iconMean[2];
      final rgb = labToRgb(l2, a2, b2);
      out.setPixelRgba(x, y, rgb[0], rgb[1], rgb[2], p.a.toInt());
    }
  }

  final png = encodePng(out);
  titleFile.writeAsBytesSync(png);
  stdout.writeln('OK: title.png 갱신, 백업: assets/title_backup_before_color_match.png');
}

bool _isBackgroundBlack(int r, int g, int b) {
  return r < 18 && g < 18 && b < 18;
}

/// 하단 흰 한글 등: 고휘도·저채도 → 색 이전 제외
bool _skipWhiteOrGreyText(int r, int g, int b) {
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  if (mx < 5) return true;
  // 거의 흰색/회색
  if (mx > 230 && (mx - mn) < 35) return true;
  return false;
}

List<double> _meanLab(List<List<double>> labs) {
  final s = [0.0, 0.0, 0.0];
  for (final l in labs) {
    s[0] += l[0];
    s[1] += l[1];
    s[2] += l[2];
  }
  final n = labs.length.toDouble();
  return [s[0] / n, s[1] / n, s[2] / n];
}

List<double> _stdLab(List<List<double>> labs, List<double> mean) {
  final s = [0.0, 0.0, 0.0];
  for (final l in labs) {
    s[0] += (l[0] - mean[0]) * (l[0] - mean[0]);
    s[1] += (l[1] - mean[1]) * (l[1] - mean[1]);
    s[2] += (l[2] - mean[2]) * (l[2] - mean[2]);
  }
  final n = labs.length.toDouble();
  return [
    math.sqrt(s[0] / n),
    math.sqrt(s[1] / n),
    math.sqrt(s[2] / n),
  ];
}

/// sRGB 0..255 → Lab (D65)
List<double> rgbToLab(int r, int g, int b) {
  final rl = _srgbToLin(r / 255.0);
  final gl = _srgbToLin(g / 255.0);
  final bl = _srgbToLin(b / 255.0);

  var x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
  var y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
  var z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;

  x /= 0.95047;
  y /= 1.00000;
  z /= 1.08883;

  x = _labF(x);
  y = _labF(y);
  z = _labF(z);

  final l = 116 * y - 16;
  final a = 500 * (x - y);
  final b_ = 200 * (y - z);
  return [l, a, b_];
}

double _labF(double t) {
  const d = 6.0 / 29.0;
  if (t > d * d * d) return math.pow(t, 1.0 / 3.0).toDouble();
  return t / (3 * d * d) + 4.0 / 29.0;
}

double _labFInv(double t) {
  const d = 6.0 / 29.0;
  if (t > d) return t * t * t;
  return 3 * d * d * (t - 4.0 / 29.0);
}

List<int> labToRgb(double l, double a, double b) {
  var y = (l + 16) / 116;
  var x = a / 500 + y;
  var z = y - b / 200;

  var x3 = _labFInv(x);
  var y3 = _labFInv(y);
  var z3 = _labFInv(z);

  x = x3 * 0.95047;
  y = y3 * 1.00000;
  z = z3 * 1.08883;

  var rl = x * 3.2404542 + y * -1.5371385 + z * -0.4985314;
  var gl = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
  var bl = x * 0.0556434 + y * -0.2040259 + z * 1.0572252;

  int ch(double u) {
    final v = _linToSrgb(u);
    return v.clamp(0, 255).round();
  }

  return [ch(rl), ch(gl), ch(bl)];
}

double _linToSrgb(double u) {
  if (u <= 0.0031308) return (12.92 * u * 255.0);
  return ((1.055 * math.pow(u, 1.0 / 2.4) - 0.055) * 255.0);
}

double _srgbToLin(double u) {
  if (u <= 0.04045) return u / 12.92;
  return math.pow((u + 0.055) / 1.055, 2.4).toDouble();
}

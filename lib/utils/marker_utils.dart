import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) 'maps_web_stub.dart';

class MarkerUtils {
  /// 텍스트(예: 순번)가 그려진 커스텀 마커 이미지를 생성합니다.
  static Future<BitmapDescriptor> createCustomMarkerBitmap(
    String text, {
    Color bgColor = Colors.blue,
    Color textColor = Colors.white,
    double size = 80,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    final Paint paint = Paint()..color = bgColor;
    final Radius radius = Radius.circular(size / 2);
    
    // 원 그리기
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0.0, 0.0, size, size),
        topLeft: radius,
        topRight: radius,
        bottomLeft: radius,
        bottomRight: radius,
      ),
      paint,
    );

    // 텍스트 그리기
    final TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size / 2.5,
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
    );
    
    painter.layout();
    painter.paint(
      canvas,
      Offset(
        (size - painter.width) / 2,
        (size - painter.height) / 2,
      ),
    );

    final img = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }
}

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    if (dart.library.html) 'maps_web_stub.dart';

enum MarkerDataStyle { solid, hollow, hotspot }

class MarkerUtils {
  /// 주변콜맵용 데이터 마커 생성
  static Future<BitmapDescriptor> createDataMarkerBitmap({
    required int size,
    required MarkerDataStyle style,
    required Color color,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double radius = size / 2;
    final Offset center = Offset(radius, radius);

    switch (style) {
      case MarkerDataStyle.solid:
        final Paint paint = Paint()..color = color..style = PaintingStyle.fill;
        canvas.drawCircle(center, radius - 4, paint);
        final Paint borderPaint = Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 3;
        canvas.drawCircle(center, radius - 4, borderPaint);
        break;
      case MarkerDataStyle.hollow:
        final Paint borderPaint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4;
        canvas.drawCircle(center, radius - 4, borderPaint);
        break;
      case MarkerDataStyle.hotspot:
        final Paint glowPaint = Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [color.withOpacity(0.9), color.withOpacity(0.1), Colors.transparent],
            [0.0, 0.7, 1.0],
          );
        canvas.drawCircle(center, radius, glowPaint);
        final Paint dotPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
        canvas.drawCircle(center, 4, dotPaint);
        break;
    }

    final img = await pictureRecorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  /// 경로지도용 핀 마커 생성 (예: 1출, 1도)
  static Future<BitmapDescriptor> createCallSegmentMarkerBitmap({
    required int callNumber,
    required bool isStart,
    required Color borderColor,
    double size = 120,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // 알약 형태의 라운드 렉트
    final double width = size;
    final double height = size * 0.55;
    final double tailHeight = 15;
    final Rect rect = Rect.fromLTWH(0, 0, width, height);
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(height / 2));

    // 테두리 두께
    final double strokeWidth = 4.0;

    // 배경색 (Dark grey)
    final Paint bgPaint = Paint()..color = const Color(0xFF272A33)..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // 테두리 (해당 콜의 색상)
    final Paint borderPaint = Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = strokeWidth;
    canvas.drawRRect(rrect, borderPaint);

    // 꼬리 그리기
    final Path tailPath = Path();
    final double midX = width / 2;
    tailPath.moveTo(midX - 10, height);
    tailPath.lineTo(midX, height + tailHeight);
    tailPath.lineTo(midX + 10, height);
    tailPath.close();
    canvas.drawPath(tailPath, bgPaint);

    // 꼬리 테두리 그리기 (V자 모양)
    final Path tailBorderPath = Path();
    tailBorderPath.moveTo(midX - 10, height);
    tailBorderPath.lineTo(midX, height + tailHeight);
    tailBorderPath.lineTo(midX + 10, height);
    canvas.drawPath(tailBorderPath, borderPaint);

    // 텍스트 준비
    final String numStr = callNumber.toString();
    final String typeStr = isStart ? '출' : '도';
    final Color typeColor = isStart ? const Color(0xFF10B981) : const Color(0xFFEF4444); // Green for start, Red for end

    // 글씨 그리기 (숫자)
    final TextPainter numPainter = TextPainter(
      text: TextSpan(
        text: numStr,
        style: TextStyle(color: Colors.white, fontSize: height * 0.6, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    );
    numPainter.layout();

    // 글씨 그리기 (출/도)
    final TextPainter typePainter = TextPainter(
      text: TextSpan(
        text: typeStr,
        style: TextStyle(color: typeColor, fontSize: height * 0.5, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    typePainter.layout();

    final double totalTextWidth = numPainter.width + 4 + typePainter.width;
    final double startX = (width - totalTextWidth) / 2;

    numPainter.paint(canvas, Offset(startX, (height - numPainter.height) / 2));
    typePainter.paint(canvas, Offset(startX + numPainter.width + 4, (height - typePainter.height) / 2));

    final int imgWidth = width.toInt();
    final int imgHeight = (height + tailHeight + strokeWidth).toInt();

    final img = await pictureRecorder.endRecording().toImage(imgWidth, imgHeight);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }
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

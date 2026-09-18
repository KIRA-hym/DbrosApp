import 'dart:io';
import 'package:flutter/material.dart';

class AiScannerDialog extends StatefulWidget {
  final File imageFile;
  const AiScannerDialog({Key? key, required this.imageFile}) : super(key: key);

  @override
  State<AiScannerDialog> createState() => _AiScannerDialogState();
}

class _AiScannerDialogState extends State<AiScannerDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              widget.imageFile,
              fit: BoxFit.contain,
            ),
          ),
          
          // Scanner Overlay
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return CustomPaint(
                  painter: _ScannerPainter(_animation.value),
                );
              },
            ),
          ),
          
          // ✨ Sparkles & Text
          Positioned(
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFC700).withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('✨', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 12),
                  Text(
                    'AI 정밀분석 진행 중...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  final double progress;

  _ScannerPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    
    // Glowing Line
    final linePaint = Paint()
      ..color = const Color(0xFFFFC700)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4.0);
      
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    // Gradient fade above the line
    final rect = Rect.fromLTRB(0, y - 50, size.width, y);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFFFC700).withOpacity(0.0),
        const Color(0xFFFFC700).withOpacity(0.3),
      ],
    );
    
    final fillPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerPainter oldDelegate) => true;
}

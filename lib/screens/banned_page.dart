import 'package:flutter/material.dart';
import '../services/font_size_service.dart';

class BannedPage extends StatelessWidget {
  const BannedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.block,
                color: Colors.redAccent,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                '접근 제한 안내',
                style: TextStyle(
                  fontSize: FontSizeService.getScaledFontSize(22),
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '관리자에 의해 사용이 제한된 계정입니다.\n문의 사항은 관리자에게 연락 바랍니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: FontSizeService.getScaledFontSize(16),
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9FA3AE),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// [drive_logs.registration_source] 용 UI (스크린샷 자동등록 구분).
class DriveLogRegistrationSource {
  DriveLogRegistrationSource._();

  /// 시스템 스크린샷 파이프 자동 저장
  static const String screenshotAuto = 'screenshot_auto';
}

/// 운행일지 등록 출처가 있을 때만 작은 칩을 표시한다.
class DriveLogSourceChip extends StatelessWidget {
  const DriveLogSourceChip({super.key, this.registrationSource});

  final String? registrationSource;

  @override
  Widget build(BuildContext context) {
    final s = registrationSource?.trim();
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    if (s == DriveLogRegistrationSource.screenshotAuto) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF2E323C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF6E717C).withValues(alpha: 0.6)),
        ),
        child: Text(
          '스샷 자동',
          style: TextStyle(
            color: const Color(0xFFFFB74D),
            fontSize: MediaQuery.sizeOf(context).width > 600 ? 11.5 : 10,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

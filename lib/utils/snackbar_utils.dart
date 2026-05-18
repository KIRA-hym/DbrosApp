import 'package:flutter/material.dart';

/// 디브로스 앱 공통 스낵바 유틸리티
/// 스낵바가 큐에 쌓여 순차적으로 뜨고 사라지면서 딜레이를 유발하는 현상을 해결하기 위해
/// 새로운 스낵바를 띄우기 전 기존 스낵바를 즉시 지우고(clearSnackBars)
/// 기본 지속 시간을 1초로 제한합니다.
void showDbrosSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 1),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration,
    ),
  );
}

extension DbrosSnackBarExtension on BuildContext {
  void showSnackBar(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 1),
  }) {
    showDbrosSnackBar(this, message, backgroundColor: backgroundColor, duration: duration);
  }
}

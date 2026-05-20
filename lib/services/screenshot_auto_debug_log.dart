import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../config/feature_flags.dart';/// adb 없이 확인할 수 있도록 스크린샷 자동등록 동선을 메모리에 누적 (Android 한정).
class ScreenshotAutoDebugLog {
  ScreenshotAutoDebugLog._();

  static const int _maxLines = 150;
  static final Queue<String> _lines = Queue<String>();

  /// 감시 시작부터의 동선 타임라인 ([kMapFeaturesEnabled] 오너 빌드에서만 저장).
  static void add(String message) {
    if (!kMapFeaturesEnabled) return;
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid) return;
    } catch (_) {
      return;
    }
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final line = '$ts  $message';
    _lines.addLast(line);
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
    debugPrint('[ShotAutoDiag] $line');
  }

  /// 최신이 위쪽 (설정 창 보기 편하게).
  static String newestFirstText() =>
      _lines.toList(growable: false).reversed.join('\n');

  static bool get isEmpty => _lines.isEmpty;

  static void clear() => _lines.clear();
}

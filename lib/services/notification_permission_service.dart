import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import 'settings_service.dart';

/// Android 13+ POST_NOTIFICATIONS — 고정 알림·스크린샷 FGS 공통.
class NotificationPermissionService {
  NotificationPermissionService._();

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<bool> isGranted() async {
    if (!_isAndroid) return false;
    return Permission.notification.isGranted;
  }

  static Future<bool> requestIfNeeded() async {
    if (!_isAndroid) return false;
    if (await isGranted()) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  /// 고정 알림 또는 스크린샷 자동저장이 켜져 있으면 앱 시작·재개 시 권한 요청.
  static Future<bool> ensureForEnabledFeatures() async {
    if (!_isAndroid) return false;
    final needs = SettingsService.statusBarQuickEnabled ||
        SettingsService.screenshotAutoRegisterEnabled;
    if (!needs) return isGranted();
    return requestIfNeeded();
  }
}

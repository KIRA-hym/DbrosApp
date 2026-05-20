import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// 스크린샷 자동등록 완료 등 일회성 알림.
class AutoRegisterNotificationService {
  AutoRegisterNotificationService._();
  static final AutoRegisterNotificationService instance = AutoRegisterNotificationService._();

  static const String _channelId = 'screenshot_auto_register';
  static const String _channelName = '스크린샷 자동등록';
  static const int _notificationId = 9101;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> initialize() async {
    if (!_isAndroid || _initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '스크린샷 콜카드 자동등록 완료 알림',
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<bool> ensureNotificationPermission() async {
    if (!_isAndroid) return false;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final req = await Permission.notification.request();
    return req.isGranted;
  }

  Future<void> showAutoRegisterComplete() async {
    if (!_isAndroid) return;
    await initialize();
    if (!await ensureNotificationPermission()) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '스크린샷 콜카드 자동등록 완료 알림',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/launcher_icon',
      ),
    );

    await _plugin.show(
      id: _notificationId,
      title: '운행일지',
      body: '운행일지 자동등록이 완료되었습니다.',
      notificationDetails: details,
    );
  }
}

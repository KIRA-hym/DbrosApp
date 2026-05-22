import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter/material.dart';
import '../app_navigator.dart';
import '../screens/write_log_page.dart';
import 'db_helper.dart';

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
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          final logId = int.tryParse(payload);
          if (logId != null) {
            _navigateToLog(logId);
          }
        }
      },
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

  void _navigateToLog(int logId) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    
    final db = await DriveLogDatabase.instance.database;
    final rows = await db.query('drive_logs', where: 'id = ?', whereArgs: [logId]);
    if (rows.isNotEmpty) {
      final log = rows.first;
      final workDate = log['work_date']?.toString();
      if (workDate != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WriteLogPage(existingLog: log, dateStr: workDate),
          ),
        );
      }
    }
  }

  Future<bool> ensureNotificationPermission() async {
    if (!_isAndroid) return false;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final req = await Permission.notification.request();
    return req.isGranted;
  }

  Future<void> showAutoRegisterComplete({int? logId}) async {
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
      _notificationId,
      '운행일지',
      '운행일지 자동등록이 완료되었습니다.',
      details,
      payload: logId?.toString(),
    );
  }
}

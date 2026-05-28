import 'dart:io' show Platform;
import 'dart:typed_data';

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

  // v2: 채널 중요도를 high로 올리기 위해 새 채널 ID 사용 (기존 채널은 중요도 변경 불가)
  static const String _channelId = 'screenshot_auto_register_v2';
  static const String _channelName = '자동등록 알림';
  static const int _notificationId = 9101;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> initialize() async {
    if (!_isAndroid || _initialized) return;

    const androidInit = AndroidInitializationSettings('@drawable/app_notification_icon');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
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

    // Importance.high → 상단 Heads-up 팝업 + 진동 허용 (카카오톡과 동일 수준)
    final channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '스크린샷 콜카드 자동등록 완료 알림',
      importance: Importance.high,
      vibrationPattern: Int64List.fromList([0, 200, 100, 200]),
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
            builder: (_) => DriveLogForm(existingLog: log, initialDate: workDate),
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

    // Importance.high + Priority.high → 카카오톡처럼 상단 Heads-up 팝업 표시
    // vibrationPattern: [딜레이, 진동, 정지, 진동] 밀리초 — 카카오톡 유사 짧은 이중 진동
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '스크린샷 콜카드 자동등록 완료 알림',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/app_notification_icon',
        vibrationPattern: Int64List.fromList([0, 200, 100, 200]),
        enableVibration: true,
      ),
    );

    await _plugin.show(
      id: _notificationId,
      title: '운행일지',
      body: '운행일지 자동등록이 완료되었습니다.',
      notificationDetails: details,
      payload: logId?.toString(),
    );
  }
}

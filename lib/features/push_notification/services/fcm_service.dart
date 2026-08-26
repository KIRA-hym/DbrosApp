import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

import '../repositories/push_repository.dart';
import '../../../app_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../services/db_helper.dart';

/// 백그라운드 메시지 핸들러 — top-level 함수여야 합니다.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FcmService] bg message: ${message.notification?.title}');
  final title = message.notification?.title;
  final body = message.notification?.body;
  if (title != null && body != null) {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await DriveLogDatabase.instance.insertNotice(title, body);
    } catch (_) {}
  }
}

/// Firebase Cloud Messaging 기기 제어 전담.
/// [init] 을 Firebase.initializeApp() 직후 한 번만 호출합니다.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) return;
    } catch (_) {
      return;
    }

    // 백그라운드 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 알림 권한 요청 (Android는 앱 진입 시 권한을 묶어서(notification, microphone) permission_handler로 별도 요청함)
    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('[FcmService] permission denied: ${settings.authorizationStatus}');
        _initialized = true;
        return;
      }
    }

    // Android 채널 설정
    if (Platform.isAndroid) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidChannel = AndroidNotificationChannel(
        'fcm_default_channel',
        '공지사항 알림',
        description: '중요 공지사항 알림을 받습니다.',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }

    // 토큰 발급 및 저장
    await _fetchAndSaveToken();

    // 토큰 갱신 감지
    _messaging.onTokenRefresh.listen((newToken) async {
      debugPrint('[FcmService] token refreshed');
      await PushRepository.instance.saveToken(newToken);
    });

    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ?? '새로운 알림';
      final body = message.notification?.body ?? '';
      debugPrint('[FcmService] fg message: $title');
      
      try {
        await DriveLogDatabase.instance.insertNotice(title, body);
      } catch (_) {}
      
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).cardTheme.color!,
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(body, style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('확인', style: TextStyle(color: Color(0xFFFFC700))),
              ),
            ],
          ),
        );
      }
    });

    // 알림 탭으로 앱이 열린 경우 (terminated)
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _handleMessage(initial);
    }

    // 백그라운드에서 알림 탭으로 앱이 foreground로 복귀
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    _initialized = true;
    debugPrint('[FcmService] initialized');
  }

  Future<void> _fetchAndSaveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await PushRepository.instance.saveToken(token);
      }
    } catch (e) {
      debugPrint('[FcmService] getToken error: $e');
    }
  }

  void _handleMessage(RemoteMessage message) {
    debugPrint('[FcmService] opened from notification: ${message.notification?.title}');
    // 필요 시 특정 화면으로 라우팅 로직 추가
  }
}

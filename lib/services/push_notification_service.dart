import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    try {
      if (kIsWeb) return; // FCM on web requires specific setup and service worker, skipping for now
      if (!Platform.isAndroid && !Platform.isIOS) return;

      // Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // Handle foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('Got a message whilst in the foreground!');
          debugPrint('Message data: ${message.data}');
          if (message.notification != null) {
            debugPrint('Message also contained a notification: ${message.notification}');
          }
        });

        // Get FCM token and save to Firestore
        await _saveTokenToFirestore();

        // Listen to token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          _updateToken(newToken);
        });
      }
    } catch (e) {
      debugPrint('PushNotificationService init error: $e');
    }
  }

  static Future<void> _saveTokenToFirestore() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _updateToken(token);
      }
    } catch (e) {
      debugPrint('FCM getToken error: $e');
    }
  }

  static Future<void> _updateToken(String token) async {
    try {
      // Create a unique id for this device based on token (using substring or hash) or just use the token itself
      // In a real app, you'd tie this to a user ID. Since there is no auth here, we use the token as the document ID
      final docId = token.length > 50 ? token.substring(0, 50) : token;
      
      await FirebaseFirestore.instance.collection('fcm_tokens').doc(docId).set({
        'token': token,
        'platform': Platform.operatingSystem,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('FCM Token saved to Firestore');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Send push request to backend via Firestore admin_push_requests
  static Future<void> requestAdminPush(String title, String body) async {
    try {
      await FirebaseFirestore.instance.collection('admin_push_requests').add({
        'title': title,
        'body': body,
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending', // pending -> processing -> success/error
      });
    } catch (e) {
      debugPrint('Error requesting admin push: $e');
      rethrow;
    }
  }
}

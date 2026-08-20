import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide NotificationVisibility;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/overlay/quick_entry_ui.dart';
import 'settings_service.dart';
import 'today_stats_notification_service.dart';

class OverlayManager {
  static OverlayEntry? _webOverlayEntry;

  static const String _keyBtnX = 'overlay_btn_x';
  static const String _keyBtnY = 'overlay_btn_y';

  static Future<void> saveButtonPosition(double x, double y) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBtnX, x);
    await prefs.setDouble(_keyBtnY, y);
  }

  static Future<OverlayPosition?> loadButtonPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_keyBtnX);
    final y = prefs.getDouble(_keyBtnY);
    if (x != null && y != null) {
      return OverlayPosition(x, y);
    }
    return null;
  }

  static Future<void> showOverlay(BuildContext context) async {
    if (kIsWeb) {
      if (_webOverlayEntry != null) return;
      _webOverlayEntry = OverlayEntry(
        builder: (context) => const WebOverlayWrapper(),
      );
      final overlay = Navigator.of(context).overlay ?? Overlay.of(context);
      overlay.insert(_webOverlayEntry!);
    } else {
      final bool status = await FlutterOverlayWindow.isPermissionGranted();
      if (!status) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }

      if (await FlutterOverlayWindow.isActive()) {
        return;
      }

      final savedPosition = await loadButtonPosition();
      final logicalSize = SettingsService.overlayButtonSizeNotifier.value;
      
      final pixelRatio = PlatformDispatcher.instance.views.first.devicePixelRatio;
      final physicalSize = (logicalSize * pixelRatio).toInt();

      if (Platform.isAndroid) {
        try {
          final flnp = FlutterLocalNotificationsPlugin();
          final androidPlugin = flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          if (androidPlugin != null) {
            await androidPlugin.deleteNotificationChannel(channelId: 'Overlay Channel');
            await androidPlugin.createNotificationChannel(
              const AndroidNotificationChannel(
                'Overlay Channel',
                'Foreground Service Channel',
                showBadge: false,
                importance: Importance.defaultImportance,
              ),
            );
          }
        } catch (e) {
          debugPrint('Failed to override overlay notification channel: \$e');
        }
      }

      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "퀵등록 실행중",
        overlayContent: "",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilitySecret,
        height: physicalSize,
        width: physicalSize,
        startPosition: savedPosition,
      );

      if (!kIsWeb && Platform.isAndroid) {
        Future.delayed(const Duration(milliseconds: 400), () {
          TodayStatsNotificationService.instance.renotifyIfEnabled();
        });
      }
    }
  }

  static Future<void> closeOverlay() async {
    if (kIsWeb) {
      _webOverlayEntry?.remove();
      _webOverlayEntry = null;
    } else {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}

class WebOverlayWrapper extends StatelessWidget {
  const WebOverlayWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      type: MaterialType.transparency,
      child: QuickEntryUI(),
    );
  }
}

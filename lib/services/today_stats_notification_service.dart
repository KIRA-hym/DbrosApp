import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:intl/intl.dart';

import '../app_navigator.dart';
import '../screens/write_log_page.dart';
import '../utils/work_date_utils.dart';
import 'auto_capture_ocr_service.dart';
import 'db_helper.dart';
import 'settings_service.dart';

/// 알림 패널 고정 알림: 오늘 수입·지출.
/// Android는 표준 플러그인 액션이 별 줄로 가므로, 네이티브 RemoteViews 한 줄 레이아웃을 사용합니다.
class TodayStatsNotificationService {
  TodayStatsNotificationService._();
  static final TodayStatsNotificationService instance = TodayStatsNotificationService._();

  static const MethodChannel _androidChannel = MethodChannel('dbros.app/today_summary');

  /// [TodaySummaryRefreshReceiver] 와 동일 (오버레이 엔진에서도 알림 갱신)
  static const String _refreshBroadcastAction = 'com.example.dbros_app.REFRESH_TODAY_SUMMARY';
  static const String _applicationId = 'com.example.dbros_app';

  bool _initialized = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> initialize({bool triggerInitialRefresh = true}) async {
    if (!_isAndroid) return;
    if (_initialized) return;

    _androidChannel.setMethodCallHandler(_onNativeMethod);
    _initialized = true;

    if (!SettingsService.statusBarQuickEnabled) {
      await cancel();
    } else if (triggerInitialRefresh) {
      await refreshFromDbIfEnabled();
    }
    AutoCaptureOcrService.instance.start();
  }

  Future<dynamic> _onNativeMethod(MethodCall call) async {
    if (call.method == 'onNotificationAction') {
      final raw = call.arguments;
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final action = map['action'] as String?;
      if (action == 'quick_register') {
        _openQuickRegisterPanel();
      } else {
        _openFullWriteScreen();
      }
    }
    return null;
  }

  void _openQuickRegisterPanel() {
    final today = WorkDateUtils.effectiveWorkDateYmd();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        bool granted = await FlutterOverlayWindow.isPermissionGranted();
        if (!granted) {
          await FlutterOverlayWindow.requestPermission();
          granted = await FlutterOverlayWindow.isPermissionGranted();
        }
        if (!granted) {
          _openFullWriteScreen();
          return;
        }

        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
        }

        await FlutterOverlayWindow.showOverlay(
          height: WindowSize.matchParent,
          width: WindowSize.matchParent,
          alignment: OverlayAlignment.center,
          visibility: NotificationVisibility.visibilityPublic,
          flag: OverlayFlag.focusPointer,
          enableDrag: false,
          overlayTitle: "Dbros Quick Register",
          overlayContent: "quick_register",
        );
        await FlutterOverlayWindow.shareData(today);
        final deadline = DateTime.now().add(const Duration(milliseconds: 900));
        while (DateTime.now().isBefore(deadline)) {
          if (await FlutterOverlayWindow.isActive()) break;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await Future<void>.delayed(const Duration(milliseconds: 280));
        try {
          await _androidChannel.invokeMethod<void>('moveTaskToBackAfterOverlay');
        } catch (_) {}
      } catch (_) {
        _openFullWriteScreen();
      }
    });
  }

  void _openFullWriteScreen() {
    final today = WorkDateUtils.effectiveWorkDateYmd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => DriveLogForm(initialDate: today),
        ),
      );
    });
  }

  Future<void> refreshFromDbIfEnabled() async {
    if (!_isAndroid || !_initialized) return;
    if (!SettingsService.statusBarQuickEnabled) return;

    final String displayDay = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final totals = await DriveLogDatabase.instance.getTodayIncomeExpense(displayDay);
    await _showNative(
      income: totals['income'] ?? 0,
      expense: totals['expense'] ?? 0,
      workDate: displayDay,
    );
  }

  Future<void> cancel() async {
    if (!_isAndroid || !_initialized) return;
    try {
      await _androidChannel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  Future<void> _showNative({
    required int income,
    required int expense,
    required String workDate,
  }) async {
    try {
      await AndroidIntent(
        action: _refreshBroadcastAction,
        package: _applicationId,
        componentName: '.TodaySummaryRefreshReceiver',
        arguments: <String, dynamic>{
          'income': income,
          'expense': expense,
          'workDate': workDate,
        },
      ).sendBroadcast();
    } catch (_) {}
    try {
      await _androidChannel.invokeMethod<void>('show', <String, dynamic>{
        'income': income,
        'expense': expense,
        'workDate': workDate,
      });
    } catch (_) {}
  }
}

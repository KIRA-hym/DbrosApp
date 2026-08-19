import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../app_navigator.dart';
import '../utils/work_date_utils.dart';
import '../main.dart' show MainWrapper;
import 'db_helper.dart';
import 'notification_permission_service.dart';
import 'settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 알림 패널 고정 알림: 오늘 수입·지출.
/// Android는 표준 플러그인 액션이 별 줄로 가므로, 네이티브 RemoteViews 한 줄 레이아웃을 사용합니다.
class TodayStatsNotificationService {
  TodayStatsNotificationService._();
  static final TodayStatsNotificationService instance = TodayStatsNotificationService._();

  static const MethodChannel _androidChannel = MethodChannel('dbros.app/today_summary');

  /// [TodaySummaryRefreshReceiver] 와 동일 (오버레이 엔진에서도 알림 갱신)
  static const String _refreshBroadcastAction = 'com.dbros.drive.REFRESH_TODAY_SUMMARY';
  static const String _applicationId = 'com.dbros.drive';

  bool _initialized = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// [applyStatusBarQuickState]: 메인 앱만 true. 오버레이 isolate에서는 false(알림 채널 핸들러만 등록).
  Future<void> initialize({
    bool triggerInitialRefresh = true,
    bool applyStatusBarQuickState = true,
  }) async {
    if (!_isAndroid) return;
    if (_initialized) return;

    _androidChannel.setMethodCallHandler(_onNativeMethod);
    _initialized = true;

    if (applyStatusBarQuickState) {
      if (!SettingsService.statusBarQuickEnabled) {
        await cancel();
      } else {
        if (triggerInitialRefresh) await refreshFromDbIfEnabled();
      }
    }
  }

  Future<dynamic> _onNativeMethod(MethodCall call) async {
    if (call.method == 'onNotificationAction') {
      final raw = call.arguments;
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final action = map['action'] as String?;
      if (action == 'quick_register') {
        _openQuickRegisterPanel();
      } else if (action == 'open_home') {
        _openHomeScreen();
      } else {
        _openFullWriteScreen();
      }
      return null;
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
          overlayTitle: 'Dbros Quick Register',
          overlayContent: '',
        );
        await FlutterOverlayWindow.shareData(today);
        final deadline = DateTime.now().add(const Duration(milliseconds: 900));
        while (DateTime.now().isBefore(deadline)) {
          if (await FlutterOverlayWindow.isActive()) break;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await Future<void>.delayed(const Duration(milliseconds: 280));
        // 오버레이 Foreground Service 알림이 상단에 오른 후 고정알림 재발행
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await renotifyIfEnabled();
        try {
          await _androidChannel.invokeMethod<void>('moveTaskToBackAfterOverlay');
        } catch (_) {}
      } catch (_) {
        _openFullWriteScreen();
      }
    });
  }

  void _openHomeScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MainWrapper(initialIndex: 0),
        ),
        (route) => false,
      );
    });
  }

  void _openFullWriteScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MainWrapper(initialIndex: 2),
        ),
        (route) => false,
      );
    });
  }

  Future<void> refreshFromDbIfEnabled() async {
    if (!_isAndroid || !_initialized) return;
    if (!SettingsService.statusBarQuickEnabled) return;
    if (!await NotificationPermissionService.isGranted()) {
      await NotificationPermissionService.requestIfNeeded();
      if (!await NotificationPermissionService.isGranted()) return;
    }

    final String displayDay = WorkDateUtils.effectiveWorkDateYmd();
    final totals = await DriveLogDatabase.instance.getTodayIncomeExpenseByWorkDate(displayDay);
    
    // Read clock state
    final prefs = await SharedPreferences.getInstance();
    final clockInStr = prefs.getString('work_timer_clock_in_time');
    final savedWorkDate = prefs.getString('work_timer_work_date');
    final savedElapsed = prefs.getInt('work_timer_elapsed_seconds') ?? 0;
    
    int elapsedSeconds = 0;
    bool isClockedIn = false;
    
    if (clockInStr != null && savedWorkDate == displayDay) {
      final clockInTime = DateTime.tryParse(clockInStr);
      if (clockInTime != null) {
        isClockedIn = true;
        final diff = DateTime.now().difference(clockInTime).inSeconds;
        elapsedSeconds = savedElapsed + diff;
        if (elapsedSeconds < 0) elapsedSeconds = 0;
      }
    }

    await _showNative(
      income: totals['income'] ?? 0,
      expense: totals['expense'] ?? 0,
      workDate: displayDay,
      elapsedSeconds: elapsedSeconds,
      isClockedIn: isClockedIn,
    );
  }

  Future<void> cancel() async {
    if (!_isAndroid || !_initialized) return;
    try {
      await _androidChannel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  /// 오버레이(Foreground Service) 알림이 최상단에 올라간 뒤,
  /// 고정알림을 cancel → 재발행하여 알림바 정렬 순서를 고정알림 상단으로 유지합니다.
  Future<void> renotifyIfEnabled() async {
    if (!_isAndroid || !_initialized) return;
    if (!SettingsService.statusBarQuickEnabled) return;
    try {
      await _androidChannel.invokeMethod<void>('cancel');
    } catch (_) {}
    // 짧은 딜레이 후 재발행 (cancel과 notify 사이 시간 확보)
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await refreshFromDbIfEnabled();
  }

  Future<bool> isQuickRegisterOverlayActive() async {
    if (!_isAndroid) return false;
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (_) {
      return false;
    }
  }

  Future<void> closeQuickRegisterOverlayIfActive() async {
    if (!await isQuickRegisterOverlayActive()) return;
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  Future<void> _showNative({
    required int income,
    required int expense,
    required String workDate,
    required int elapsedSeconds,
    required bool isClockedIn,
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
          'elapsedSeconds': elapsedSeconds,
          'isClockedIn': isClockedIn,
        },
      ).sendBroadcast();
    } catch (_) {}
    try {
      await _androidChannel.invokeMethod<void>('show', <String, dynamic>{
        'income': income,
        'expense': expense,
        'workDate': workDate,
        'elapsedSeconds': elapsedSeconds,
        'isClockedIn': isClockedIn,
      });
    } catch (_) {}
  }
}

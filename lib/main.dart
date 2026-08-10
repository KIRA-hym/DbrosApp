import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/remote_config_service.dart';
import 'features/push_notification/services/fcm_service.dart';
import 'providers/today_stats_provider.dart';
import 'providers/work_timer_provider.dart';
import 'providers/form_state_provider.dart';
import 'widgets/app_glass_dialog.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app_navigator.dart' show rootNavigatorKey;
import 'main_navigation.dart';
import 'screens/write_log_page.dart';
import 'screens/home_page.dart';
import 'screens/log_list_page.dart';
import 'screens/stats_page.dart';
import 'screens/settings_page.dart';
import 'screens/login_page.dart';
import 'screens/banned_page.dart';
import 'services/auth_service.dart';
import 'services/db_helper.dart';
import 'services/expense_repository.dart';
import 'services/feature_usage_service.dart';
import 'services/rewarded_ad_service.dart';
import 'screens/expense_home_page.dart';
import 'services/settings_service.dart';
import 'services/font_size_service.dart';
import 'services/subscription_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'widgets/ad_banner_widget.dart';
import 'widgets/shorebird_update_host.dart';
import 'services/today_stats_notification_service.dart';
import 'services/notification_permission_service.dart';
import 'services/backup_service.dart';
import 'services/screenshot_auto_register_service.dart';
import 'utils/work_date_utils.dart';
import 'utils/pro_feature_guard.dart';
import 'services/shorebird_update_service.dart';
import 'theme/app_theme.dart';
import 'providers/guide_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'dummy_api_key_for_web_preview',
          appId: '1:1234567890:web:abcdef123456',
          messagingSenderId: '1234567890',
          projectId: 'dbros-dummy-project',
        ),
      );
    } else {
      // 5초 타임아웃: Firebase 초기화가 네트워크 이슈로 무한 대기하는 것 방지
      try {
        await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      } on Exception catch (e) {
        debugPrint('[main] Firebase.initializeApp error/timeout: $e');
      }
    }
    // RemoteConfigService는 네트워크 fetchAndActivate 포함 → 백그라운드 처리
    unawaited(RemoteConfigService().initialize());
    // FCM init은 getToken() 등 네트워크 호출 포함 → 백그라운드 처리
    unawaited(FcmService.instance.init());
  } catch (e) {
    debugPrint('Firebase init error (Web preview?): $e');
  }

  // MobileAds.initialize()는 Google 서버 통신 포함 → 블로킹 방지, 백그라운드 처리
  unawaited(Future(() async {
    try {
      await MobileAds.instance.initialize();
      RewardedAdService.loadAd();
    } catch (e) {
      debugPrint('AdMob init error: $e');
    }
  }));
  
  // 폴드 펼침·태블릿 가로 모드 포함 (Z Fold 6 등)
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SettingsService.init();
  await FeatureUsageService.init();
  await FontSizeService.loadFontSize();
  await initializeDateFormatting('ko_KR', null);
  await SubscriptionService.init();

  DriveLogDatabase.afterLogsChanged = () {
    TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    TodayStatsProvider.instance.refresh();
    WorkTimerProvider.instance?.autoClockInIfNeeded();
  };
  ExpenseRepository.afterExpensesChanged = () {
    ExpenseHomePage.requestRefresh();
  };
  if (!kIsWeb && Platform.isAndroid) {
    await NotificationPermissionService.ensureForEnabledFeatures();
  }
  // TodayStatsNotification 초기화에서 refreshFromDbIfEnabled → _showNative →
  // Android native invokeMethod 가 타임아웃 없이 블로킹할 수 있음
  // 채널 핸들러 등록(즉시)만 하고, 첫 refresh는 runApp() 이후 백그라운드로 처리
  await TodayStatsNotificationService.instance.initialize(
    triggerInitialRefresh: false, // ← 블로킹 방지
  );

  if (!kIsWeb && Platform.isAndroid) {
    unawaited(ScreenshotAutoRegisterService.instance.syncWithSettingsPreference());
  }

  SettingsService.isFeatureUnlockedNotifier.addListener(() {
    if (!SettingsService.isFeatureUnlockedNotifier.value) {
      if (!kIsWeb && Platform.isAndroid) {
        ScreenshotAutoRegisterService.instance.syncWithSettingsPreference();
        TodayStatsNotificationService.instance.cancel();
      }
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TodayStatsProvider.instance..refresh()),
        ChangeNotifierProvider(create: (_) => AuthService.instance),
        ChangeNotifierProvider(create: (_) => WorkTimerProvider()),
        ChangeNotifierProvider(create: (_) => GuideProvider.instance),
      ],
      child: const DbrosApp(),
    ),
  );

  Future.microtask(() async {
    try {
      await BackupService.runAutoBackupIfNeeded();
    } catch (_) {}
    // runApp() 이후 백그라운드에서 알림 새로고침 (네이티브 채널 블로킹 방지)
    try {
      await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    } catch (_) {}
  });
}

@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await SettingsService.init();
  await FeatureUsageService.init();
  await FontSizeService.loadFontSize();
  await initializeDateFormatting('ko_KR', null);
  await TodayStatsNotificationService.instance.initialize(
    triggerInitialRefresh: false,
    applyStatusBarQuickState: false,
  );
  runApp(const _QuickRegisterOverlayApp());
}

class _QuickRegisterOverlayApp extends StatelessWidget {
  const _QuickRegisterOverlayApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.amoledTheme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const _QuickRegisterOverlayRoot(),
    );
  }
}

class _QuickRegisterOverlayRoot extends StatefulWidget {
  const _QuickRegisterOverlayRoot();

  @override
  State<_QuickRegisterOverlayRoot> createState() => _QuickRegisterOverlayRootState();
}

class _QuickRegisterOverlayRootState extends State<_QuickRegisterOverlayRoot> {
  String _initialDate = WorkDateUtils.effectiveWorkDateYmd();
  /// 오버레이 엔진이 캐시되면 [DriveLogForm] State가 유지되므로, 퀵등록을 열 때마다 증가시켜 신규 폼을 만든다.
  int _quickFormSession = 0;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      final text = event?.toString().trim() ?? '';
      if (text.isNotEmpty && mounted) {
        setState(() {
          _initialDate = text;
          _quickFormSession++;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DriveLogForm(
      key: ValueKey<String>('quick_overlay_$_quickFormSession'),
      initialDate: _initialDate,
      quickPanel: true,
      fromOverlay: true,
    );
  }
}

class DbrosApp extends StatelessWidget {
  const DbrosApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: FontSizeService.fontNotifier,
      builder: (context, fontSize, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsService.isOwnerModeNotifier,
          builder: (context, isOwnerMode, child) {
            return ValueListenableBuilder<ThemeMode>(
              valueListenable: SettingsService.themeModeNotifier,
              builder: (context, themeMode, child) {
                return ValueListenableBuilder<bool>(
                  valueListenable: SettingsService.isAmoledBlackNotifier,
                  builder: (context, isAmoledBlack, child) {
                    return GestureDetector(
                      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: MaterialApp(
                navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final isFold = mq.size.width >= 600.0; // ResponsiveLayout.breakpoint
              final double headlineBonus = isFold ? 2.0 : 0.0;

              return MediaQuery(
                data: mq.copyWith(textScaler: FontSizeService.combinedTextScaler(mq)),
                child: Theme(
                  data: themeMode == ThemeMode.light 
                    ? AppTheme.lightTheme.copyWith(
                        textTheme: _buildScaledTextTheme(AppTheme.lightTheme.textTheme, headlineBonus),
                        appBarTheme: AppTheme.lightTheme.appBarTheme.copyWith(
                          titleTextStyle: AppTheme.lightTheme.appBarTheme.titleTextStyle?.copyWith(
                            fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus),
                          ),
                        ),
                        bottomNavigationBarTheme: AppTheme.lightTheme.bottomNavigationBarTheme.copyWith(
                          selectedLabelStyle: TextStyle(
                            fontFamily: 'GmarketSans',
                            fontWeight: FontWeight.w700,
                            fontSize: FontSizeService.getScaledFontSize(12),
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontFamily: 'GmarketSans',
                            fontWeight: FontWeight.w700,
                            fontSize: FontSizeService.getScaledFontSize(12),
                          ),
                        ),
                      )
                    : (isAmoledBlack ? AppTheme.amoledTheme : AppTheme.darkTheme).copyWith(
                        textTheme: _buildScaledTextTheme((isAmoledBlack ? AppTheme.amoledTheme : AppTheme.darkTheme).textTheme, headlineBonus),
                        appBarTheme: (isAmoledBlack ? AppTheme.amoledTheme : AppTheme.darkTheme).appBarTheme.copyWith(
                          titleTextStyle: (isAmoledBlack ? AppTheme.amoledTheme : AppTheme.darkTheme).appBarTheme.titleTextStyle?.copyWith(
                            fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus),
                          ),
                        ),
                        bottomNavigationBarTheme: (isAmoledBlack ? AppTheme.amoledTheme : AppTheme.darkTheme).bottomNavigationBarTheme.copyWith(
                          selectedLabelStyle: TextStyle(
                            fontFamily: 'GmarketSans',
                            fontWeight: FontWeight.w700,
                            fontSize: FontSizeService.getScaledFontSize(12),
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontFamily: 'GmarketSans',
                            fontWeight: FontWeight.w700,
                            fontSize: FontSizeService.getScaledFontSize(12),
                          ),
                        ),
                      ),
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: Consumer<AuthService>(
              builder: (context, auth, child) {
                if (auth.status == AuthStatus.uninitialized) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF121418),
                    body: Center(child: CircularProgressIndicator(color: Color(0xFFFFC700))),
                  );
                } else if (auth.status == AuthStatus.unauthenticated) {
                  return const LoginPage();
                } else if (auth.status == AuthStatus.banned) {
                  return const BannedPage();
                }
                return const MainWrapper();
              },
            ),
          ),
        );
              },
            );
          },
        );
      },
    );
      },
    );
  }

  TextTheme _buildScaledTextTheme(TextTheme base, double headlineBonus) {
    return base.copyWith(
      bodyLarge: base.bodyLarge?.copyWith(fontSize: FontSizeService.getScaledFontSize(16), fontWeight: FontWeight.w400),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: FontSizeService.getScaledFontSize(14), fontWeight: FontWeight.w400),
      bodySmall: base.bodySmall?.copyWith(fontSize: FontSizeService.getScaledFontSize(12), fontWeight: FontWeight.w400),
      headlineLarge: base.headlineLarge?.copyWith(fontSize: FontSizeService.getScaledFontSize(24 + headlineBonus), fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: FontSizeService.getScaledFontSize(20 + headlineBonus), fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus), fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus), fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontSize: FontSizeService.getScaledFontSize(16 + headlineBonus), fontWeight: FontWeight.w700),
      titleSmall: base.titleSmall?.copyWith(fontSize: FontSizeService.getScaledFontSize(14 + headlineBonus), fontWeight: FontWeight.w700),
      labelLarge: base.labelLarge?.copyWith(fontSize: FontSizeService.getScaledFontSize(14), fontWeight: FontWeight.w700),
      labelMedium: base.labelMedium?.copyWith(fontSize: FontSizeService.getScaledFontSize(12), fontWeight: FontWeight.w700),
      labelSmall: base.labelSmall?.copyWith(fontSize: FontSizeService.getScaledFontSize(10), fontWeight: FontWeight.w400),
    );
  }
}

class MainWrapper extends StatefulWidget {
  final int initialIndex;
  const MainWrapper({super.key, this.initialIndex = 0});
  
  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> with WidgetsBindingObserver {
  late int _selectedIndex;
  Timer? _workDateNotificationTick;
  String _lastNotifiedWorkDateYmd = WorkDateUtils.effectiveWorkDateYmd();
  StreamSubscription<List<SharedMediaFile>>? _shareIntentSub;
  StreamSubscription<int>? _tabEventSub;
  DateTime? _lastShorebirdCheckTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedIndex = widget.initialIndex;
    _lastNotifiedWorkDateYmd = WorkDateUtils.effectiveWorkDateYmd();
    _workDateNotificationTick = Timer.periodic(const Duration(minutes: 1), (_) => _refreshNotificationIfWorkDateChanged());
    _setupShareIntentListener();
    _lastShorebirdCheckTime = DateTime.now();
    _tabEventSub = mainTabEventController.stream.listen((index) {
      if (mounted) {
        setState(() => _selectedIndex = index);
      }
    });
  }

  /// 스크린샷·갤러리 등에서 이미지 공유 시 일지 작성 화면으로 연결 (**Android 전용**).
  void _setupShareIntentListener() {
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid) return;
    } catch (_) {
      return;
    }

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (!mounted || value.isEmpty) return;
      _openWriteLogWithSharedFiles(value);
      ReceiveSharingIntent.instance.reset();
    });

    _shareIntentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (!mounted || value.isEmpty) return;
        _openWriteLogWithSharedFiles(value);
      },
      onError: (_) {},
    );
  }

  void _openWriteLogWithSharedFiles(List<SharedMediaFile> files) {
    SharedMediaFile? pick;
    for (final f in files) {
      final mime = f.mimeType ?? '';
      if (f.type == SharedMediaType.image || mime.startsWith('image/')) {
        pick = f;
        break;
      }
    }
    pick ??= files.first;
    final path = pick.path.trim();
    if (path.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => DriveLogForm(sharedImagePath: path),
        ),
      );
    });
  }

  void _refreshNotificationIfWorkDateChanged() {
    final next = WorkDateUtils.effectiveWorkDateYmd();
    if (next != _lastNotifiedWorkDateYmd) {
      _lastNotifiedWorkDateYmd = next;
      TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      if (!kIsWeb && Platform.isAndroid) {
        FlutterOverlayWindow.closeOverlay().catchError((_) => false);
      }
    } else if (state == AppLifecycleState.resumed) {
      final next = WorkDateUtils.effectiveWorkDateYmd();
      if (next != _lastNotifiedWorkDateYmd) {
        _lastNotifiedWorkDateYmd = next;
      }
      RemoteConfigService().forceFetch().then((updated) {
        if (updated && mounted) {
          setState(() {});
        }
      });
      if (!kIsWeb && Platform.isAndroid) {
        unawaited(NotificationPermissionService.ensureForEnabledFeatures());
      }
      TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
      if (!kIsWeb && Platform.isAndroid) {
        unawaited(ScreenshotAutoRegisterService.instance.syncWithSettingsPreference());
        unawaited(ScreenshotAutoRegisterService.instance.checkRecentScreenshotOnResume());
      }
      
      final now = DateTime.now();
      if (_lastShorebirdCheckTime == null || now.difference(_lastShorebirdCheckTime!).inHours >= 1) {
        _lastShorebirdCheckTime = now;
        ShorebirdUpdateService.instance.checkAndUpdate();
      }

      if (_workDateNotificationTick == null || !_workDateNotificationTick!.isActive) {
        _workDateNotificationTick = Timer.periodic(const Duration(minutes: 1), (_) => _refreshNotificationIfWorkDateChanged());
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _workDateNotificationTick?.cancel();
    }
  }

  @override
  void dispose() {
    _shareIntentSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _workDateNotificationTick?.cancel();
    _tabEventSub?.cancel();
    super.dispose();
  }

  final List<Widget> _pages = [
    const HomePage(),
    const LogListPage(),
    DriveLogForm(),
    const StatsPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return MainTabScope(
      selectTab: (index) {
        if (index >= 0 && index < _pages.length) {
          setState(() => _selectedIndex = index);
          if (index == 0) TodayStatsProvider.instance.refresh();
        }
      },
      child: ShorebirdUpdateHost(
        child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
            TodayStatsProvider.instance.refresh();
          } else {
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Theme.of(context).cardTheme.color,
                title: const Text('앱 종료', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: const Text('앱을 종료하시겠습니까?', style: TextStyle(color: Colors.white)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('아니오', style: TextStyle(color: Colors.grey)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text('예', style: TextStyle(color: Theme.of(context).primaryColor)),
                  ),
                ],
              ),
            );
            if (shouldExit == true) {
              SystemNavigator.pop();
            }
          }
        },
        child: Scaffold(
      resizeToAvoidBottomInset: false,
      body: _pages[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBannerWidget(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              "Copyright 2026 Dbros. All rights reserved.",
              style: TextStyle(
                color: const Color(0xFF6E717C),
                fontSize: FontSizeService.getScaledFontSize(10),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Theme.of(context).bottomNavigationBarTheme.backgroundColor,
              selectedItemColor: Theme.of(context).bottomNavigationBarTheme.selectedItemColor, 
              unselectedItemColor: Theme.of(context).bottomNavigationBarTheme.unselectedItemColor, 
              selectedFontSize: FontSizeService.getScaledFontSize(12),
              unselectedFontSize: FontSizeService.getScaledFontSize(12),
              selectedLabelStyle: TextStyle(
                fontFamily: 'GmarketSans',
                fontWeight: FontWeight.w700,
                fontSize: FontSizeService.getScaledFontSize(12),
              ),
              unselectedLabelStyle: TextStyle(
                fontFamily: 'GmarketSans',
                fontWeight: FontWeight.w700,
                fontSize: FontSizeService.getScaledFontSize(12),
              ),
              currentIndex: _selectedIndex,
              onTap: (index) async {
                if (index == 3) { // Stats tab
                  ProFeatureGuard.checkAndRun(
                    context: context,
                    featureKey: 'stats',
                    canUseFree: () async => false, // Stats has 0 free uses according to logic
                    canUseWithAd: FeatureUsageService.canUseStatsWithAd,
                    onGranted: () {
                      setState(() => _selectedIndex = index);
                    },
                  );
                  return;
                }

                if (_selectedIndex == 2 && index != 2 && FormStateProvider.isWriteFormDirtyNotifier.value) {
                  final bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AppGlassDialog(
                      title: '작성을 취소하시겠습니까?',
                      content: '입력 중인 내용은 저장되지 않습니다.',
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('계속 작성', style: TextStyle(color: Colors.white70)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('작성 취소', style: TextStyle(color: Color(0xFFFF6B6B))),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  FormStateProvider.isWriteFormDirtyNotifier.value = false;
                }

                if (index == 0) {
                  TodayStatsProvider.instance.refresh();
                  RemoteConfigService().forceFetch().then((updated) {
                    if (updated && mounted) setState(() {});
                  });
                }
                setState(() => _selectedIndex = index);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_filled), activeIcon: Icon(Icons.home), label: '홈'),
                BottomNavigationBarItem(icon: Icon(Icons.list_alt), activeIcon: Icon(Icons.list_alt), label: '\u{baa9}\u{b85d}'),
                BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), activeIcon: Icon(Icons.add_circle), label: '\u{c791}\u{c131}'),
                BottomNavigationBarItem(icon: Icon(Icons.bar_chart), activeIcon: Icon(Icons.bar_chart), label: '\u{d1b5}\u{acc4}'),
                BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: '\u{c124}\u{c815}'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<double>(
        valueListenable: FontSizeService.fontNotifier,
        builder: (context, fontSize, child) {
          return ValueListenableBuilder<bool>(
            valueListenable: SettingsService.showFloatingButtonsNotifier,
            builder: (context, showFloatingButtons, child) {
              return showFloatingButtons ? Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: "font_increase",
                    onPressed: () async {
                      final mq = MediaQuery.of(context);
                      await FontSizeService.increaseFontSizeForMediaQuery(mq);
                    },
                    backgroundColor: const Color(0xFFFFC700),
                    mini: true,
                    child: const Icon(Icons.zoom_in, color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: "font_decrease",
                    onPressed: () async {
                      await FontSizeService.decreaseFontSize();
                    },
                    backgroundColor: const Color(0xFFFFC700),
                    mini: true,
                    child: const Icon(Icons.zoom_out, color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: "font_reset",
                    onPressed: () async {
                      await FontSizeService.resetFontSize();
                    },
                    backgroundColor: Theme.of(context).cardTheme.color!,
                    mini: true,
                    child: const Icon(Icons.refresh, color: Color(0xFFFFC700)),
                  ),
                ],
              ) : const SizedBox.shrink();
            },
          );
        },
      ),
        ),
      ),
    ),
    );
  }
}

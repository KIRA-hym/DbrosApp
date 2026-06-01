import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/remote_config_service.dart';
import 'features/push_notification/services/fcm_service.dart';
import 'providers/today_stats_provider.dart';
import 'dart:io' show Platform;
import 'dart:ui';

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
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'widgets/ad_banner_widget.dart';
import 'widgets/shorebird_update_host.dart';
import 'services/today_stats_notification_service.dart';
import 'services/notification_permission_service.dart';
import 'services/backup_service.dart';
import 'services/screenshot_auto_register_service.dart';
import 'utils/work_date_utils.dart';
import 'utils/pro_feature_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await RemoteConfigService().initialize();
    await FcmService.instance.init();
  } catch (e) {
    debugPrint('Firebase init error (Web preview?): $e');
  }

  try {
    await MobileAds.instance.initialize();
    RewardedAdService.loadAd();
  } catch (e) {
    debugPrint('AdMob init error: $e');
  }
  
  // 폴드 펼침·태블릿 가로 모드 포함 (Z Fold 6 등)
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SettingsService.init();
  await FeatureUsageService.init();
  await FontSizeService.loadFontSize();
  await initializeDateFormatting('ko_KR', null);

  DriveLogDatabase.afterLogsChanged = () {
    TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    TodayStatsProvider.instance.refresh();
  };
  ExpenseRepository.afterExpensesChanged = () {
    ExpenseHomePage.requestRefresh();
  };
  if (!kIsWeb && Platform.isAndroid) {
    await NotificationPermissionService.ensureForEnabledFeatures();
  }
  await TodayStatsNotificationService.instance.initialize();

  if (!kIsWeb && Platform.isAndroid) {
    unawaited(ScreenshotAutoRegisterService.instance.syncWithSettingsPreference());
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TodayStatsProvider.instance..refresh()),
        ChangeNotifierProvider(create: (_) => AuthService.instance),
      ],
      child: const DbrosApp(),
    ),
  );

  Future.microtask(() async {
    try {
      await BackupService.runAutoBackupIfNeeded();
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
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'GmarketSans',
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
                  data: ThemeData(
                    brightness: Brightness.dark,
                    fontFamily: 'GmarketSans',
                    scaffoldBackgroundColor: const Color(0xFF121418), 
                    primaryColor: const Color(0xFFFFC700), 
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFFFFC700),
                      surface: Color(0xFF1F222A), 
                    ),
                    appBarTheme: AppBarTheme(
                      backgroundColor: const Color(0xFF1F222A),
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      surfaceTintColor: Colors.transparent,
                      centerTitle: true,
                      titleTextStyle: TextStyle(
                        fontFamily: 'GmarketSans',
                        fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus), 
                        fontWeight: FontWeight.w700, 
                        color: Colors.white
                      ),
                    ),
                    bottomNavigationBarTheme: BottomNavigationBarThemeData(
                      backgroundColor: const Color(0xFF121418),
                      selectedItemColor: const Color(0xFFFFC700),
                      unselectedItemColor: const Color(0xFF6E717C),
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
                    textTheme: TextTheme(
                      bodyLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(16), color: Colors.white, fontWeight: FontWeight.w400),
                      bodyMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(14), color: Colors.white, fontWeight: FontWeight.w400),
                      bodySmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(12), color: Colors.white, fontWeight: FontWeight.w400),
                      headlineLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(24 + headlineBonus), color: Colors.white, fontWeight: FontWeight.w700),
                      headlineMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(20 + headlineBonus), color: Colors.white, fontWeight: FontWeight.w700),
                      headlineSmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus), color: Colors.white, fontWeight: FontWeight.w700),
                      titleLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(18 + headlineBonus), color: Colors.white, fontWeight: FontWeight.w700),
                      titleMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(16 + headlineBonus), color: Colors.white, fontWeight: FontWeight.w700),
                      titleSmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(14 + headlineBonus), color: Colors.white, fontWeight: FontWeight.w700),
                      labelLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(14), color: Colors.white, fontWeight: FontWeight.w700),
                      labelMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(12), color: Colors.white, fontWeight: FontWeight.w700),
                      labelSmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(10), color: Colors.white, fontWeight: FontWeight.w400),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedIndex = widget.initialIndex;
    _lastNotifiedWorkDateYmd = WorkDateUtils.effectiveWorkDateYmd();
    _workDateNotificationTick = Timer.periodic(const Duration(minutes: 1), (_) => _refreshNotificationIfWorkDateChanged());
    _setupShareIntentListener();
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
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
            TodayStatsProvider.instance.refresh();
          } else {
            SystemNavigator.pop();
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
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF121418),
              selectedItemColor: const Color(0xFFFFC700), 
              unselectedItemColor: const Color(0xFF6E717C), 
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
              onTap: (index) {
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
                    backgroundColor: const Color(0xFF1F222A),
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

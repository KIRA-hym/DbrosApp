import 'dart:async';
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
import 'services/db_helper.dart';
import 'services/expense_repository.dart';
import 'screens/expense_home_page.dart';
import 'services/settings_service.dart';
import 'services/font_size_service.dart';
import 'services/today_stats_notification_service.dart';
import 'utils/work_date_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  await SettingsService.init();
  await FontSizeService.loadFontSize();
  await initializeDateFormatting('ko_KR', null);

  DriveLogDatabase.afterLogsChanged = () {
    TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
    HomePage.requestRefresh();
  };
  ExpenseRepository.afterExpensesChanged = () {
    ExpenseHomePage.requestRefresh();
  };
  await TodayStatsNotificationService.instance.initialize();

  runApp(const DbrosApp());
}

@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await SettingsService.init();
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
        return GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: FontSizeService.combinedTextScaler(mq)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            theme: ThemeData(
              brightness: Brightness.dark,
              fontFamily: 'GmarketSans',
              scaffoldBackgroundColor: const Color(0xFF121418), 
              primaryColor: const Color(0xFFFFC700), 
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFFFFC700),
                surface: Color(0xFF1F222A), 
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFF121418),
                elevation: 0,
                centerTitle: true,
                titleTextStyle: TextStyle(
                  fontFamily: 'GmarketSans',
                  fontSize: FontSizeService.getScaledFontSize(18), 
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
                headlineLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(24), color: Colors.white, fontWeight: FontWeight.w700),
                headlineMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(20), color: Colors.white, fontWeight: FontWeight.w700),
                headlineSmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(18), color: Colors.white, fontWeight: FontWeight.w700),
                titleLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(18), color: Colors.white, fontWeight: FontWeight.w700),
                titleMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(16), color: Colors.white, fontWeight: FontWeight.w700),
                titleSmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(14), color: Colors.white, fontWeight: FontWeight.w700),
                labelLarge: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(14), color: Colors.white, fontWeight: FontWeight.w700),
                labelMedium: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(12), color: Colors.white, fontWeight: FontWeight.w700),
                labelSmall: TextStyle(fontFamily: 'GmarketSans', fontSize: FontSizeService.getScaledFontSize(10), color: Colors.white, fontWeight: FontWeight.w400),
              ),
            ),
            home: const MainWrapper(),
          ),
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
    if (state == AppLifecycleState.resumed) {
      final next = WorkDateUtils.effectiveWorkDateYmd();
      if (next != _lastNotifiedWorkDateYmd) {
        _lastNotifiedWorkDateYmd = next;
      }
      TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
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
          if (index == 0) HomePage.requestRefresh();
        }
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_selectedIndex != 0) {
            setState(() => _selectedIndex = 0);
            HomePage.requestRefresh();
          } else {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                setState(() => _selectedIndex = index);
                if (index == 0) HomePage.requestRefresh();
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
    );
  }
}

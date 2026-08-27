import 'dart:io' show Platform;

import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import 'my_info_page.dart';
import '../main_navigation.dart';
import 'write_log_page.dart';
import 'admin_user_list_page.dart';
import 'log_list_page.dart';
import 'stats_page.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../widgets/guide_content_widget.dart';
import '../providers/guide_provider.dart';
import '../utils/work_date_utils.dart';
import '../services/auth_service.dart';
import '../config/feature_flags.dart';
import '../services/backup_service.dart';
import '../services/screenshot_auto_debug_log.dart';
import '../services/screenshot_auto_register_service.dart';
import '../services/settings_service.dart';
import '../services/feature_usage_service.dart';
import '../services/overlay_manager.dart';
import '../services/shorebird_update_service.dart';
import '../services/apk_update_service.dart';
import '../utils/responsive_layout.dart';
import '../widgets/app_glass_dialog.dart';
import '../widgets/apk_update_dialog.dart';
import '../services/rewarded_ad_service.dart';
import '../widgets/list_manage_dialog.dart';
import '../widgets/bordered_section.dart';
import '../widgets/responsive_body.dart';
import '../widgets/settings/theme_settings_section.dart';
import '../services/today_stats_notification_service.dart';
import 'ocr_debug_page.dart';
import '../services/db_helper.dart';
import '../utils/geocoding_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/call_point_export_service.dart';
import '../features/push_notification/widgets/admin_push_dialog.dart';
import 'notice_list_page.dart';
import '../services/google_sheets_share_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final _baseFeeCon = TextEditingController(
    text: SettingsService.baseFeeRate.toString(),
  );
  final _perTripInsCon = TextEditingController(
    text: SettingsService.perTripInsurance.toString(),
  );
  String _insuranceType = SettingsService.insuranceType;

  // [원복] _quickRegisterOpacity 제거: 퀵등록 투명도 슬라이더 기능 원복으로 불필요
  bool _statusBarQuickEnabled = SettingsService.statusBarQuickEnabled;
  bool _autoBackupEnabled = SettingsService.autoBackupEnabled;
  String _imagePurgePeriod = SettingsService.imagePurgePeriod;
  bool _screenshotAutoRegisterEnabled =
      SettingsService.screenshotAutoRegisterEnabled;
  final _gasWebhookCon = TextEditingController(
    text: SettingsService.gasWebhookUrl,
  );
  bool _hasGasChanges = false;

  final GlobalKey _keyMyInfo = GlobalKey();
  final GlobalKey _keyFeeInsurance = GlobalKey();
  final GlobalKey _keyCategoryManager = GlobalKey();
  final GlobalKey _keyThemeSettings = GlobalKey();
  final GlobalKey _keyScreenshotAuto = GlobalKey();
  final GlobalKey _keyBackupRestore = GlobalKey();
  final GlobalKey _keyStorage = GlobalKey();
  final GlobalKey _keyAppConvenience = GlobalKey();
  final GlobalKey _keyStatusBarQuick = GlobalKey();
  final GlobalKey _keyOverlayQuick = GlobalKey();
  final GlobalKey _keyAddressSearchMode = GlobalKey();
  final GlobalKey _keyCallPointShare = GlobalKey();
  TutorialCoachMark? _tutorialCoachMark;

  final double _initialBaseFeeRate = SettingsService.baseFeeRate;
  final String _initialInsuranceType = SettingsService.insuranceType;
  final int _initialPerTripInsurance = SettingsService.perTripInsurance;

  bool _hasFeeChanges = false;
  bool _hasInsuranceChanges = false;

  String _appVersionLabel = '';
  String _shorebirdPatchLabel = '';

  int _versionTapCount = 0;
  Timer? _versionTapTimer;

  int _unreadNoticeCount = 0;
  bool _hasPostponedUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersionLabel();
    _loadShorebirdPatchLabel();
    _loadUnreadNoticeCount();
    _loadPostponedUpdateStatus();
    _loadApkUpdateStatus();

    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.addListener(_onGuideRequested);
  }

  Future<void> _loadApkUpdateStatus() async {
    final hasApk = await ApkUpdateService.instance.checkForUpdate();
    if (mounted) setState(() {});
  }

  Future<void> _loadPostponedUpdateStatus() async {
    final hasPostponed = await ShorebirdUpdateService.instance
        .hasPostponedUpdate();
    if (mounted) setState(() => _hasPostponedUpdate = hasPostponed);
  }

  Future<void> _loadShorebirdPatchLabel() async {
    final info = await ShorebirdUpdateService.instance.getPatchInfo();
    if (!mounted) return;
    if (!info.available) {
      setState(() => _shorebirdPatchLabel = 'OTA: 미지원 빌드');
      return;
    }
    final cur = info.current;
    final pending = info.pending;
    final pendingStr = pending != null && pending != cur
        ? ' → #$pending 대기'
        : '';
    setState(() {
      _shorebirdPatchLabel = cur != null
          ? 'OTA 패치: #$cur$pendingStr'
          : 'OTA 패치: 기본(릴리스)';
    });
  }

  Future<void> _loadUnreadNoticeCount() async {
    final count = await DriveLogDatabase.instance.getUnreadNoticeCount();
    if (mounted) setState(() => _unreadNoticeCount = count);
  }

  Future<void> _loadAppVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final buildNumVal = int.tryParse(info.buildNumber);
      final String displayBuild;
      if (buildNumVal != null) {
        final buildNum = buildNumVal % 100;
        displayBuild = buildNum.toString().padLeft(2, '0');
      } else {
        displayBuild = info.buildNumber.padLeft(2, '0');
      }
      setState(() {
        _appVersionLabel = 'v${info.version}.$displayBuild';
      });
    } catch (_) {
      if (mounted) setState(() => _appVersionLabel = '');
    }
  }

  void _checkFeeChanges() {
    final currentValue = double.tryParse(_baseFeeCon.text) ?? 20.0;
    setState(() {
      _hasFeeChanges = currentValue != _initialBaseFeeRate;
    });
  }

  void _checkInsuranceChanges() {
    setState(() {
      bool typeChanged = _insuranceType != _initialInsuranceType;
      bool amountChanged = false;
      if (_insuranceType == 'per_trip') {
        final currentPerTrip = int.tryParse(_perTripInsCon.text) ?? 0;
        amountChanged = currentPerTrip != _initialPerTripInsurance;
      }

      _hasInsuranceChanges = typeChanged || amountChanged;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    Provider.of<GuideProvider>(
      context,
      listen: false,
    ).removeListener(_onGuideRequested);
    _baseFeeCon.dispose();
    _perTripInsCon.dispose();
    _versionTapTimer?.cancel();
    super.dispose();
  }

  List<Widget> _settingsSections(TextStyle versionStyle) {
    return [
      Container(
        key: _keyMyInfo,
        child: _buildListManageButton(
          title: '내 정보',
          icon: Icons.person,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MyInfoPage()),
            );
          },
        ),
      ),
      _buildNoticeSection(),
      Container(key: _keyThemeSettings, child: const ThemeSettingsSection()),
      Container(key: _keyBackupRestore, child: _buildBackupRestoreSettings()),
      Container(
        key: _keyFeeInsurance,
        child: _buildListManageButton(
          title: '수수료 설정',
          icon: Icons.monetization_on_outlined,
          onTap: _showFeeDialog,
        ),
      ),
      _buildListManageButton(
        title: '보험료 설정',
        icon: Icons.shield_outlined,
        onTap: _showInsuranceDialog,
      ),
      Container(key: _keyCategoryManager, child: _buildProgramListSettings()),
      _buildExpenseListSettings(),
      _buildIncomeListSettings(),
      Container(key: _keyAppConvenience, child: _buildAppConvenienceSettings()),
      if (SettingsService.isOwnerMode)
        Container(
          key: _keyCallPointShare,
          child: _buildCallPointShareSettings(),
        ),
      if (SettingsService.isOwnerMode && !kIsWeb && Platform.isAndroid)
        _buildOcrParseLogSettings(),
      Container(key: _keyStorage, child: _buildStorageSettings()),
      if (SettingsService.isOwnerMode && !kIsWeb && kMapFeaturesEnabled)
        _buildBatchGeocodeSettings(),
      if (SettingsService.isOwnerMode) _buildAdminPushSection(),
      if (SettingsService.isOwnerMode && kMonetizationEnabled)
        _buildProModeTestToggle(),
      _buildVersionInfoSection(versionStyle),
    ];
  }

  void _onGuideRequested() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    if (guideProvider.pendingGuideTarget == 'settings') {
      _startGuideWhenReady();
    }
  }

  void _startGuideWhenReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showSettingsGuide();
      }
    });
  }

  void _showSettingsGuide() {
    final guideProvider = Provider.of<GuideProvider>(context, listen: false);
    guideProvider.clearGuide();

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "myInfo",
        keyTarget: _keyMyInfo,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            builder: (context, controller) {
              return GuideContentWidget(
                title: "내정보 및 혜택 관리",
                description:
                    "회원가입 정보, 이메일 문의(고객지원), 프로모션 코드 입력 및 프리미엄 구독 관리를 할 수 있는 메뉴입니다.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "themeSettings",
        keyTarget: _keyThemeSettings,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            builder: (context, controller) {
              return GuideContentWidget(
                title: "화면 및 폰트 설정",
                description:
                    "앱의 테마를 변경하고, 메인 목록의 폰트 크기 조절 버튼 표시 여부를 설정할 수 있습니다.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      if (_keyBackupRestore.currentContext != null)
        TargetFocus(
          identify: "backupRestore",
          keyTarget: _keyBackupRestore,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "데이터 백업 및 복원",
                  description: "기기 변경 시 기록해둔 데이터를 백업하고 복원할 수 있습니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      TargetFocus(
        identify: "feeInsurance",
        keyTarget: _keyFeeInsurance,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            builder: (context, controller) {
              return GuideContentWidget(
                title: "수수료 및 보험료 설정",
                description:
                    "사용하시는 대리 프로그램의 수수료율과 건당 보험료를 설정해두면 일지 작성 시 자동 계산됩니다.",
                controller: controller,
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "categoryManager",
        keyTarget: _keyCategoryManager,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            builder: (context, controller) {
              return GuideContentWidget(
                title: "항목 관리",
                description:
                    "대리 프로그램 이름이나 지출 항목(주유비, 식대 등)을 자유롭게 추가/수정할 수 있습니다.",
                controller: controller,
              );
            },
          ),
        ],
      ),
    ];

    if (_keyAppConvenience.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "appConvenience",
          keyTarget: _keyAppConvenience,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "앱 편의 기능",
                  description:
                      "콜카드 스크린샷 자동저장, 플로팅 버튼, 고정 알림 등 편의 기능을 설정하는 영역입니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }
    if (_keyStatusBarQuick.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "statusBarQuick",
          keyTarget: _keyStatusBarQuick,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "고정 알림 상태바",
                  description:
                      "스마트폰 상단 알림창에 오늘 순익을 항상 띄워둡니다. 활성화 시 다음 날 오전 9시까지 무료로 적용됩니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }
    if (_keyScreenshotAuto.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "screenshotAuto",
          keyTarget: _keyScreenshotAuto,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "스크린샷 일지 자동저장",
                  description:
                      "콜카드를 캡처하면 일지가 자동 작성됩니다. 활성화 시 다음 날 오전 9시까지 무제한 자동 등록이 가능합니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }
    if (_keyOverlayQuick.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "overlayQuick",
          keyTarget: _keyOverlayQuick,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "퀵등록 플로팅버튼",
                  description:
                      "화면 위에 항상 떠있는 간편 등록 버튼입니다. 활성화 시 오전 9시까지 횟수 제한 없이 띄울 수 있습니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keyAddressSearchMode.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "addressSearchMode",
          keyTarget: _keyAddressSearchMode,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "주소 자동완성 방식",
                  description: "출/도착지 입력 시 추천받을 주소의 기준(시/군/구 등)을 설정합니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keyCallPointShare.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "callPointShare",
          keyTarget: _keyCallPointShare,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "콜포인트 공유",
                  description: "기사님들 간에 유용한 장소나 정보를 지도로 공유하는 커뮤니티 기능입니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    if (_keyStorage.currentContext != null) {
      targets.add(
        TargetFocus(
          identify: "storage",
          keyTarget: _keyStorage,
          alignSkip: Alignment.bottomRight,
          contents: [
            TargetContent(
              builder: (context, controller) {
                return GuideContentWidget(
                  title: "데이터 정리",
                  description: "오래된 데이터를 삭제하여 앱 용량을 최적화합니다.",
                  controller: controller,
                );
              },
            ),
          ],
        ),
      );
    }

    _tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      textSkip: "건너뛰기",
      paddingFocus: 10,
      opacityShadow: 0.8,
      useSafeArea: true,
      beforeFocus: (target) async {
        final currentContext = target.keyTarget?.currentContext;
        if (currentContext != null) {
          try {
            await Scrollable.ensureVisible(
              currentContext,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
            // wait a tiny bit for the scroll view to settle its layout
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            // ignore scroll errors
          }
        }
      },
      onFinish: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
        return true;
      },
      onClickTarget: (target) {},
      onClickOverlay: (target) {},
      onSkip: () {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
        return true;
      },
    )..show(context: context);
  }

  void _showFeeDialog() {
    AppGlassDialog.show<void>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.monetization_on_outlined,
        title: "수수료 설정",
        contentWidget: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "기본 수수료율 (%)",
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseFeeCon,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF2C2F3D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              label: '취소',
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              label: '저장',
              filled: true,
              onPressed: () async {
                await SettingsService.setBaseFeeRate(
                  double.tryParse(_baseFeeCon.text) ?? 20.0,
                );
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("수수료 설정이 저장되었습니다.")),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showInsuranceDialog() {
    AppGlassDialog.show<void>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.shield_outlined,
        title: "보험료 설정",
        contentWidget: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<String>(
                  title: const Text(
                    "적용 안 함",
                    style: TextStyle(color: Colors.white),
                  ),
                  value: 'none',
                  groupValue: _insuranceType,
                  activeColor: Theme.of(context).primaryColor,
                  onChanged: (val) {
                    setDialogState(() => _insuranceType = val!);
                    setState(() => _insuranceType = val!);
                  },
                ),
                RadioListTile<String>(
                  title: const Text(
                    "건당 보험료",
                    style: TextStyle(color: Colors.white),
                  ),
                  value: 'per_trip',
                  groupValue: _insuranceType,
                  activeColor: Theme.of(context).primaryColor,
                  onChanged: (val) {
                    setDialogState(() => _insuranceType = val!);
                    setState(() => _insuranceType = val!);
                  },
                ),
                if (_insuranceType == 'per_trip')
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                    ),
                    child: TextField(
                      controller: _perTripInsCon,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "1건당 차감 금액 (원)",
                        labelStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF2C2F3D),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              label: '취소',
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              label: '저장',
              filled: true,
              onPressed: () async {
                await SettingsService.setInsuranceType(_insuranceType);
                await SettingsService.setPerTripInsurance(
                  int.tryParse(_perTripInsCon.text) ?? 0,
                );
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("보험료 설정이 저장되었습니다.")),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppConvenienceSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "앱 편의 기능",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              "고정 알림 상태바",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              "알림 패널에 오늘 순익 표시",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            value: _statusBarQuickEnabled,
            activeColor: Theme.of(context).primaryColor,
            onChanged: (value) async {
              if (value && !SettingsService.isFeatureUnlocked()) {
                _showAdRewardDialog(context, 'status_bar', () async {
                  if (!await _requirePermission([Permission.notification], "알림")) return;
                  await SettingsService.setStatusBarQuickEnabled(true);
                  await TodayStatsNotificationService.instance
                      .refreshFromDbIfEnabled();
                  if (!mounted) return;
                  setState(() => _statusBarQuickEnabled = true);
                });
                return;
              }

              if (value) {
                if (!await _requirePermission([Permission.notification], "알림")) return;
              }

              await SettingsService.setStatusBarQuickEnabled(value);
              if (value) {
                await TodayStatsNotificationService.instance
                    .refreshFromDbIfEnabled();
              } else {
                await TodayStatsNotificationService.instance.cancel();
              }

              if (!mounted) return;
              setState(() => _statusBarQuickEnabled = value);
            },
          ),
          SwitchListTile(
            key: _keyScreenshotAuto,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              "스크린샷 일지 자동저장",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              "스크린샷 찍을 때 일지 등록",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            value: _screenshotAutoRegisterEnabled,
            activeColor: Theme.of(context).primaryColor,
            onChanged: (value) async {
              if (value && !SettingsService.isFeatureUnlocked()) {
                _showAdRewardDialog(context, 'auto_screenshot', () async {
                  if (!kIsWeb && Platform.isAndroid) {
                    final storageStatus = await Permission.storage.request();
                    final photosStatus = await Permission.photos.request();

                    if (!storageStatus.isGranted && !photosStatus.isGranted) {
                      if (!mounted) return;
                      AppGlassDialog.show<void>(
                        context: context,
                        dialog: AppGlassDialog(
                          icon: Icons.folder_off_outlined,
                          title: '권한 설정 필요',
                          content:
                              '스크린샷 자동 저장을 위해 파일 접근 권한이 필요합니다.\n\n[설정] > [권한]에서 저장공간(파일/미디어) 접근 권한을 허용해 주세요.',
                          actions: [
                            Builder(
                              builder: (ctx) => GlassDialogCancelButton(
                                onPressed: () => Navigator.pop(ctx),
                                label: '취소',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (ctx) => Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    openAppSettings();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).primaryColor,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('설정으로 이동'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                  }
                  await SettingsService.setScreenshotAutoRegisterEnabled(true);
                  await ScreenshotAutoRegisterService.instance
                      .syncWithSettingsPreference();
                  if (!mounted) return;
                  setState(() => _screenshotAutoRegisterEnabled = true);
                });
                return;
              }

              if (value) {
                if (!kIsWeb && Platform.isAndroid) {
                  final storageStatus = await Permission.storage.request();
                  final photosStatus = await Permission.photos.request();
                  if (!storageStatus.isGranted && !photosStatus.isGranted) {
                    if (!mounted) return;
                    AppGlassDialog.show<void>(
                      context: context,
                      dialog: AppGlassDialog(
                        icon: Icons.folder_off_outlined,
                        title: '권한 설정 필요',
                        content:
                            '스크린샷 자동 저장을 위해 파일 접근 권한이 필요합니다.\n\n[설정] > [권한]에서 저장공간(파일/미디어) 접근 권한을 허용해 주세요.',
                        actions: [
                          Builder(
                            builder: (ctx) => GlassDialogCancelButton(
                              onPressed: () => Navigator.pop(ctx),
                              label: '취소',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Builder(
                            builder: (ctx) => Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  openAppSettings();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).primaryColor,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text(
                                  '설정으로 이동',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
                }
              }

              await SettingsService.setScreenshotAutoRegisterEnabled(value);
              await ScreenshotAutoRegisterService.instance
                  .syncWithSettingsPreference();

              if (!mounted) return;
              setState(() => _screenshotAutoRegisterEnabled = value);
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsService.overlayQuickRegisterNotifier,
            builder: (context, overlayEnabled, _) {
              return Column(
                children: [
                  SwitchListTile(
                    key: _keyOverlayQuick,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "퀵등록 플로팅버튼",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "화면에 빠른 등록 버튼 띄우기",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    value: overlayEnabled,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (value) async {
                      if (value && !SettingsService.isFeatureUnlocked()) {
                        _showAdRewardDialog(context, 'overlay_quick', () async {
                          if (!await _requestSystemAlertWindowPermission())
                            return;
                          await SettingsService.setOverlayQuickRegisterEnabled(
                            true,
                          );
                          await OverlayManager.showOverlay(context);
                        });
                        return;
                      }

                      if (value) {
                        if (!await _requestSystemAlertWindowPermission())
                          return;
                      }

                      await SettingsService.setOverlayQuickRegisterEnabled(
                        value,
                      );
                      if (value) {
                        await OverlayManager.showOverlay(context);
                      } else {
                        await OverlayManager.closeOverlay();
                      }
                    },
                  ),
                  if (overlayEnabled)
                    ValueListenableBuilder<double>(
                      valueListenable:
                          SettingsService.overlayButtonSizeNotifier,
                      builder: (context, btnSize, _) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              const Text(
                                "버튼 크기 조절",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: btnSize,
                                  min: 40.0,
                                  max: 100.0,
                                  activeColor: Theme.of(context).primaryColor,
                                  onChanged: (val) {
                                    SettingsService.setOverlayButtonSize(val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),

          ValueListenableBuilder<String>(
            valueListenable: SettingsService.addressSearchModeNotifier,
            builder: (context, currentMode, _) {
              return ListTile(
                key: _keyAddressSearchMode,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '주소 자동완성 방식',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  '입력 시 추천해 주는 기준 선택',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: DropdownButton<String>(
                  value: currentMode,
                  dropdownColor: Theme.of(context).cardTheme.color,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'both', child: Text('기록+주소 (기본)')),
                    DropdownMenuItem(value: 'history', child: Text('과거 기록만')),
                    DropdownMenuItem(value: 'address', child: Text('기본 주소만')),
                  ],
                  onChanged: (val) {
                    if (val != null) SettingsService.setAddressSearchMode(val);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _requirePermission(List<Permission> permissions, String permName) async {
    bool anyGranted = false;
    for (var p in permissions) {
      final status = await p.request();
      if (status.isGranted) {
        anyGranted = true;
      }
    }
    if (anyGranted) return true;
    
    if (!mounted) return false;
    final bool? goToSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: '$permName 권한 허용 필요',
        content: '기능을 사용하려면 기기 설정에서 $permName 권한을 허용해 주세요.',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('설정으로 이동', style: TextStyle(color: Theme.of(context).primaryColor)),
          ),
        ],
      ),
    );
    if (goToSettings == true) {
      await openAppSettings();
    }
    return false;
  }

  Future<bool> _requestSystemAlertWindowPermission() async {
    if (!await _requirePermission([Permission.systemAlertWindow], '다른 앱 위에 표시')) return false;
    if (!await _requirePermission([Permission.microphone], '마이크')) return false;
    return true;
  }

  Widget _buildSettingsScrollBody({
    required double horizontalPadding,
    required double groupSpacing,
    required TextStyle versionStyle,
  }) {
    final sections = _settingsSections(versionStyle);
    final isExpanded = ResponsiveLayout.isExpanded(context);

    if (isExpanded) {
      const gridGap = 16.0;
      final gridSections = sections.length > 1
          ? sections.sublist(0, sections.length - 1)
          : sections;
      final versionSection = sections.isNotEmpty ? sections.last : null;
      return SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.all(horizontalPadding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - gridGap) / 2;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < gridSections.length; i += 2)
                  Padding(
                    padding: EdgeInsets.only(bottom: gridGap),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: gridSections[i]),
                          SizedBox(width: gridGap),
                          Expanded(
                            child: i + 1 < gridSections.length
                                ? gridSections[i + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (versionSection != null) versionSection,
              ],
            );
          },
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) SizedBox(height: groupSpacing),
            sections[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveLayout.isTablet(context);
    final horizontalPadding = ResponsiveLayout.horizontalPadding(context);
    final groupSpacing = isTablet ? 28.0 : 24.0;

    final versionFs = isTablet ? 12.0 : 11.0;
    final versionStyle = TextStyle(
      fontFamily: 'GmarketSans',
      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
      fontSize: versionFs,
      fontWeight: FontWeight.w500,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).cardTheme.color!,
        title: Text(
          '운행 일지 설정',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
      ),
      body: ResponsiveBody(
        fullWidthWhenExpanded: true,
        child: _buildSettingsScrollBody(
          horizontalPadding: horizontalPadding,
          groupSpacing: groupSpacing,
          versionStyle: versionStyle,
        ),
      ),
    );
  }

  Widget _buildVersionInfoSection(TextStyle versionStyle) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;
    final label = _appVersionLabel.isEmpty ? '…' : _appVersionLabel;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 0.75,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '버전정보',
                style: versionStyle.copyWith(fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _handleVersionTap,
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.all(4.0),
                      child: Text(label, style: versionStyle),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleVersionTap() {
    _versionTapCount++;
    _versionTapTimer?.cancel();
    _versionTapTimer = Timer(const Duration(milliseconds: 500), () {
      _versionTapCount = 0;
    });

    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      final currentState = SettingsService.isOwnerMode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentState ? '오너 모드가 활성화되어 있습니다.' : '관리자 권한이 없습니다.'),
        ),
      );
    }
  }

  Widget _buildSettingsGroup(
    String title,
    List<Widget> children, {
    bool showChangeButton = false,
    VoidCallback? onSave,
  }) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (showChangeButton && onSave != null)
                ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "변경",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          SizedBox(height: spacing),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    Color titleColor = const Color(0xFFFFFFFF),
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title, style: TextStyle(color: titleColor, fontSize: 16)),
      trailing: Icon(Icons.chevron_right, color: Color(0xFF6E717C), size: 16),
      onTap: onTap,
    );
  }

  Widget _buildRadioTile(String title, String value, {Widget? child}) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final leftPadding = isTablet ? 40.0 : 32.0;
    final bottomPadding = isTablet ? 16.0 : 12.0;

    return Column(
      children: [
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
            ),
          ),
          value: value,
          groupValue: _insuranceType,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (v) {
            setState(() {
              _insuranceType = v!;
            });
            _checkInsuranceChanges();
          },
        ),
        if (child != null)
          Padding(
            padding: EdgeInsets.only(left: leftPadding, bottom: bottomPadding),
            child: child,
          ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController con,
    String label, {
    VoidCallback? onChanged,
  }) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final borderRadius = isTablet ? 16.0 : 12.0;
    final horizontalPadding = isTablet ? 20.0 : 16.0;
    final verticalPadding = isTablet ? 16.0 : 12.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: TextField(
        controller: con,
        keyboardType: TextInputType.number,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color:
                (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
          ),
          floatingLabelStyle: TextStyle(
            color: Color(0xFFFFC700),
            fontWeight: FontWeight.bold,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
        ),
        onChanged: (value) {
          if (onChanged != null) onChanged();
        },
        onSubmitted: (value) {
          if (onChanged != null) onChanged();
        },
      ),
    );
  }

  Widget _buildProgramListSettings() {
    return _buildListManageButton(
      title: '프로그램 목록관리',
      icon: Icons.apps_rounded,
      onTap: () => ListManageDialog.show(
        context: context,
        title: '프로그램 목록관리',
        icon: Icons.apps_rounded,
        items: List.from(SettingsService.programList),
        hintText: '새 프로그램 이름',
        subtitleBuilder: (context, item) =>
            ProgramTogglesWidget(programName: item),
        onAdd: (item) async {
          final list = List<String>.from(SettingsService.programList)
            ..add(item);
          await SettingsService.setProgramList(list);
          return true;
        },
        onDelete: (_, item) async {
          final list = List<String>.from(SettingsService.programList)
            ..remove(item);
          await SettingsService.setProgramList(list);
        },
      ),
    );
  }

  Widget _buildExpenseListSettings() {
    return _buildListManageButton(
      title: '지출 항목 관리',
      icon: Icons.money_off_rounded,
      accentColor: const Color(0xFFFF5252),
      onTap: () => ListManageDialog.show(
        context: context,
        title: '지출 항목 관리',
        icon: Icons.money_off_rounded,
        items: List.from(SettingsService.expenseList),
        hintText: '새 지출 항목 이름',
        accentColor: const Color(0xFFFF5252),
        onAdd: (item) async {
          await SettingsService.addExpenseItem(item);
          return true;
        },
        onDelete: (_, item) async {
          await SettingsService.removeExpenseItem(item);
        },
      ),
    );
  }

  Widget _buildIncomeListSettings() {
    return _buildListManageButton(
      title: '수익 항목 관리',
      icon: Icons.add_card_rounded,
      accentColor: Colors.lightBlueAccent,
      onTap: () => ListManageDialog.show(
        context: context,
        title: '수익 항목 관리',
        icon: Icons.add_card_rounded,
        items: List.from(SettingsService.incomeList),
        hintText: '새 수익 항목 이름',
        accentColor: Colors.lightBlueAccent,
        onAdd: (item) async {
          await SettingsService.addIncomeItem(item);
          return true;
        },
        onDelete: (_, item) async {
          await SettingsService.removeIncomeItem(item);
        },
      ),
    );
  }

  void _showGuideSelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '어떤 가이드를 보시겠어요?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.home,
                  color: Theme.of(context).primaryColor,
                ),
                title: Text(
                  '홈 화면 가이드',
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  GuideProvider.instance.startGuide('home');
                  MainTabScope.maybeOf(context)?.selectTab(0);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.list,
                  color: Theme.of(context).primaryColor,
                ),
                title: Text(
                  '목록 화면 가이드',
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  GuideProvider.instance.startGuide('list');
                  MainTabScope.maybeOf(context)?.selectTab(1);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.description,
                  color: Theme.of(context).primaryColor,
                ),
                title: Text(
                  '상세 화면 가이드',
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  GuideProvider.instance.startGuide('detail');
                  MainTabScope.maybeOf(context)?.selectTab(1); // List 탭으로 이동

                  final effectiveDate = WorkDateUtils.effectiveWorkDateYmd();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DailyLogListPage(
                        dateStr: effectiveDate,
                        dateTitle: effectiveDate,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.edit,
                  color: Theme.of(context).primaryColor,
                ),
                title: Text(
                  '작성 화면 가이드',
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  GuideProvider.instance.startGuide('write');
                  // Move to Write Log Page
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DriveLogForm(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.bar_chart, color: Color(0xFFFFC700)),
                title: Text(
                  '통계 화면 가이드',
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  GuideProvider.instance.startGuide('stats');
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const StatsPage()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.settings, color: Colors.grey),
                title: Text(
                  '설정 화면 가이드',
                  style: TextStyle(
                    color:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  GuideProvider.instance.startGuide('settings');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListManageButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color accentColor = const Color(0xFFFFC700),
  }) {
    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: accentColor, size: 22),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color:
                (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).dividerColor,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildOcrParseLogSettings() {
    return _buildSettingsGroup('디버그 및 로그', [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.receipt_long, color: Color(0xFFFFC700)),
        title: Text(
          '콜카드 인식 로그',
          style: TextStyle(
            color:
                (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
            fontSize: 16,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: Color(0xFF6E717C), size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OcrDebugPage()),
          );
        },
      ),
    ]);
  }

  void _showBackupOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color!,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '백업 위치 선택',
                style: TextStyle(
                  color:
                      (Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.white),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.phone_android, color: Color(0xFFFFC700)),
                title: Text(
                  '단말기 (Downloads) 저장',
                  style: TextStyle(
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.backupToLocalDevice(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.cloud_upload, color: Color(0xFF2196F3)),
                title: Text(
                  '구글 드라이브 등 공유 저장',
                  style: TextStyle(
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.backupToDrive(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRestoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color!,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '복원 위치 선택',
                style: TextStyle(
                  color:
                      (Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.white),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.phone_android, color: Color(0xFFFFC700)),
                title: Text(
                  '단말기에서 가져오기',
                  style: TextStyle(
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.restoreFromFilePicker(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.cloud_download, color: Color(0xFF2196F3)),
                title: Text(
                  '구글 드라이브에서 가져오기',
                  style: TextStyle(
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.restoreFromDrivePicker(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackupRestoreSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    final lastBackupStr = SettingsService.lastAutoBackupDate;
    final displayDate = lastBackupStr.isEmpty
        ? '없음'
        : lastBackupStr.split('T').first;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "데이터 백업/복원",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showBackupOptions();
                  },
                  icon: Icon(
                    Icons.cloud_upload,
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                  label: Text("백업"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 20 : 16,
                      vertical: isTablet ? 12 : 8,
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showRestoreOptions();
                  },
                  icon: Icon(
                    Icons.cloud_download,
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                  label: Text("복원"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 20 : 16,
                      vertical: isTablet ? 12 : 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Divider(color: Color(0xFF2C2F38), height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              "7일 주기 자동 백업 (ZIP)",
              style: TextStyle(
                color:
                    (Theme.of(context).textTheme.bodyLarge?.color ??
                    Colors.white),
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              "최근 자동 백업일: $displayDate",
              style: TextStyle(color: Color(0xFF6E717C), fontSize: 12),
            ),
            value: _autoBackupEnabled,
            activeThumbColor: Theme.of(context).primaryColor,
            activeColor: Theme.of(context).primaryColor.withOpacity(0.3),
            onChanged: (value) async {
              await SettingsService.setAutoBackupEnabled(value);
              setState(() {
                _autoBackupEnabled = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCallPointShareSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "콜포인트(좌표) 공유",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final confirm = await AppGlassDialog.show<bool>(
                  context: context,
                  dialog: AppGlassDialog(
                    icon: Icons.cloud_upload_rounded,
                    title: '내 좌표 전체 공유하기',
                    content:
                        '내 운행일지에 등록된 모든 정상 좌표(출발지/경유지/도착지)를 주변콜맵 구글 시트로 전송하시겠습니까?\n\n이 작업은 익명으로 안전하게 전송되며 다른 기사님들과 꿀콜을 공유하는 데 쓰입니다.',
                    actions: [
                      Builder(
                        builder: (ctx) => GlassDialogCancelButton(
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                      ),
                      Builder(
                        builder: (ctx) => GlassDialogConfirmButton(
                          label: '전송하기',
                          onPressed: () => Navigator.pop(ctx, true),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  // Show loading
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  final result =
                      await GoogleSheetsShareService.shareMyCoordinates(
                        AuthService.instance.userDoc?['uid'] ?? 'unknown',
                      );

                  if (context.mounted) Navigator.pop(context); // Hide loading

                  if (context.mounted) {
                    if (result.success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.message == '성공'
                                ? '좌표가 성공적으로 공유되었습니다!'
                                : result.message,
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('좌표 공유에 실패했습니다: ${result.message}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: Icon(Icons.cloud_upload_rounded, color: Colors.white),
              label: Text("내 좌표 전체 공유하기 (클라우드)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE91E63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await CallPointExportService.exportToCsv(context);
                  },
                  icon: Icon(
                    Icons.share,
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                  label: Text("내보내기"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 20 : 16,
                      vertical: isTablet ? 12 : 8,
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await CallPointExportService.importFromCsv(context);
                  },
                  icon: Icon(
                    Icons.download,
                    color:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                  ),
                  label: Text("가져오기"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor:
                        (Theme.of(context).textTheme.bodyLarge?.color ??
                        Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 20 : 16,
                      vertical: isTablet ? 12 : 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "데이터 정리",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing),
          DropdownButtonFormField<String>(
            value: _imagePurgePeriod,
            dropdownColor: Theme.of(context).cardTheme.color!,
            decoration: InputDecoration(
              labelText: "오래된 콜카드 이미지 정리 기준",
              labelStyle: TextStyle(color: Color(0xFF6E717C), fontSize: 13),
              floatingLabelStyle: TextStyle(
                color: Color(0xFFFFC700),
                fontWeight: FontWeight.bold,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2C2F38)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2C2F38)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFC700)),
              ),
            ),
            style: TextStyle(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
              fontSize: 15,
            ),
            items: [
              DropdownMenuItem(value: 'none', child: Text("선택 안 함")),
              DropdownMenuItem(value: '3_months', child: Text("3개월 이전 이미지")),
              DropdownMenuItem(value: '6_months', child: Text("6개월 이전 이미지")),
            ],
            onChanged: (value) async {
              if (value != null) {
                await SettingsService.setImagePurgePeriod(value);
                setState(() {
                  _imagePurgePeriod = value;
                });
              }
            },
          ),
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final confirm = await AppGlassDialog.show<bool>(
                  context: context,
                  dialog: AppGlassDialog(
                    icon: Icons.cleaning_services_outlined,
                    title: '이미지 정리',
                    content: _imagePurgePeriod == 'none'
                        ? "설정된 정리 기준이 없습니다. 정리 기준을 '3개월 이전' 또는 '6개월 이전'으로 선택한 뒤 다시 시도해 주세요."
                        : "선택한 이미지 정리 기준(${_imagePurgePeriod == '3_months' ? '3개월' : '6개월'} 이전)에 따라 오래된 원본 이미지를 디스크에서 제거하시겠습니까?\n\n※ 정산 및 운행일지 기록은 그대로 보존됩니다.",
                    actions: [
                      Builder(
                        builder: (ctx) => GlassDialogCancelButton(
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                      ),
                      if (_imagePurgePeriod != 'none')
                        Builder(
                          builder: (ctx) => GlassDialogConfirmButton(
                            label: '지금 정리',
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ),
                    ],
                  ),
                );
                if (confirm == true) {
                  final deleted = await BackupService.purgeOldImages();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$deleted건의 오래된 콜카드 이미지가 정리되었습니다.")),
                  );
                }
              },
              icon: Icon(Icons.cleaning_services_outlined, color: Colors.black),
              label: Text("이미지 정리"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(vertical: isTablet ? 14 : 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runBatchGeocodeUpdate() async {
    final db = await DriveLogDatabase.instance.database;
    final logs = await db.query(
      'drive_logs',
      where:
          'start_lat IS NULL OR start_lng IS NULL OR end_lat IS NULL OR end_lng IS NULL',
    );

    if (logs.isEmpty) {
      if (!mounted) return;
      showDbrosSnackBar(context, '업데이트할 좌표 정보가 없습니다. (모든 데이터가 최신입니다)');
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BatchGeocodeProgressDialog(logs: logs),
    );
  }

  Widget _buildProModeTestToggle() {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.isPremiumUserNotifier,
      builder: (context, isPremium, child) {
        return Container(
          decoration: BorderedSection.decoration(context, borderRadius: 12),
          child: ListTile(
            title: Text(
              '👑 [TEST] 프리미엄 기능 (무료/유료 전환)',
              style: TextStyle(
                color:
                    (Theme.of(context).textTheme.bodyLarge?.color ??
                    Colors.white),
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '개발자 테스트용 강제 전환 스위치',
              style: TextStyle(
                color:
                    (Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.white)
                        .withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            trailing: Switch(
              value: isPremium,
              activeColor: Theme.of(context).primaryColor,
              onChanged: (value) async {
                await SettingsService.setPromoPremium(value);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminPushSection() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(Icons.campaign_rounded, size: 20),
              label: Text(
                '공지사항 푸시 발송 (관리자)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _openAdminPushDialog(),
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(Icons.person, size: 20),
              label: Text(
                '회원 관리 (관리자)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminUserListPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeSection() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NoticeListPage()),
                );
                _loadUnreadNoticeCount();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications, size: 20),
                  SizedBox(width: 8),
                  Text('알림목록', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_unreadNoticeCount > 0) ...[
                    SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_unreadNoticeCount',
                        style: TextStyle(
                          color:
                              (Theme.of(context).textTheme.bodyLarge?.color ??
                              Colors.white),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                _showGuideSelectionSheet(context);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline, size: 20),
                  SizedBox(width: 8),
                  Text('앱이용가이드', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAdminPushDialog() {
    AdminPushDialog.show(context);
  }

  Widget _buildBatchGeocodeSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "과거 데이터 좌표 일괄 업데이트",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing),
          Text(
            '과거에 등록되어 좌표가 비어있는 운행일지 데이터들을 추려, 주소를 좌표로 자동 변환하여 채워 넣습니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _runBatchGeocodeUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(Icons.pin_drop),
              label: Text(
                '좌표 일괄 업데이트 시작',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdRewardDialog(
    BuildContext context,
    String featureKey,
    VoidCallback onSuccess,
  ) async {
    final confirm = await AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.ondemand_video,
        title: '기능 일시 잠금 해제',
        content:
            '30초 광고를 시청하시면 내일 오전 9시까지 꺼짐 없이 편의기능이 무료로 유지됩니다.\n\n광고를 시청하시겠습니까?',
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              onPressed: () => Navigator.pop(ctx, false),
              label: '취소',
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              label: '시청하기',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFC700)),
        ),
      );

      bool rewardEarned = false;

      RewardedAdService.showAd(
        onEarnedReward: () async {
          rewardEarned = true;
        },
        onAdClosed: () async {
          if (context.mounted) Navigator.pop(context); // Close loading dialog
          if (rewardEarned) {
            await FeatureUsageService.grantDailyPass(featureKey);
            onSuccess();
          }
        },
        onAdFailed: () {
          if (context.mounted) {
            Navigator.pop(context); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('광고 로드에 실패했습니다. 나중에 다시 시도해주세요.')),
            );
          }
        },
      );
    }
  }
}

/// 좌표 일괄 업데이트 진행 다이얼로그 (진행 상태는 State에 보관).
class _BatchGeocodeProgressDialog extends StatefulWidget {
  const _BatchGeocodeProgressDialog({required this.logs});

  final List<Map<String, dynamic>> logs;

  @override
  State<_BatchGeocodeProgressDialog> createState() =>
      _BatchGeocodeProgressDialogState();
}

class _BatchGeocodeProgressDialogState
    extends State<_BatchGeocodeProgressDialog> {
  int _processed = 0;
  int _updated = 0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runBatch());
  }

  Future<void> _runBatch() async {
    final db = await DriveLogDatabase.instance.database;

    for (final log in widget.logs) {
      if (!mounted) break;

      final startLoc = log['start_location']?.toString() ?? '';
      final endLoc = log['end_location']?.toString() ?? '';
      final updateData = <String, dynamic>{};

      if (log['start_lat'] == null && startLoc.isNotEmpty) {
        final loc = await GeocodingUtils.getCoordinateFromAddressFallback(
          startLoc,
        );
        if (loc != null) {
          updateData['start_lat'] = loc.latitude;
          updateData['start_lng'] = loc.longitude;
        }
      }

      if (log['end_lat'] == null && endLoc.isNotEmpty) {
        final loc = await GeocodingUtils.getCoordinateFromAddressFallback(
          endLoc,
        );
        if (loc != null) {
          updateData['end_lat'] = loc.latitude;
          updateData['end_lng'] = loc.longitude;
        }
      }

      if (updateData.isNotEmpty) {
        await db.update(
          'drive_logs',
          updateData,
          where: 'id = ?',
          whereArgs: [log['id']],
        );
        _updated++;
      }

      if (mounted) {
        setState(() => _processed++);
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!kIsWeb) {
      await DriveLogDatabase.instance.syncCallPointsFromDriveLogs();
    }

    if (mounted) {
      setState(() => _isFinished = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.logs.length;
    final progress = total == 0 ? 0.0 : (_processed / total).clamp(0.0, 1.0);

    return AppGlassDialog(
      icon: Icons.place_outlined,
      title: _isFinished ? '좌표 일괄 업데이트 완료' : '좌표 일괄 업데이트 중',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$_processed / $total 건 처리',
            style: TextStyle(
              color:
                  (Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.white),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            _isFinished ? '좌표 반영 $_updated건' : '주소를 좌표로 변환하는 중입니다…',
            style: TextStyle(color: Color(0xFF9FA3AE), fontSize: 13),
          ),
          SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _isFinished ? 1.0 : progress,
              minHeight: 8,
              color: Theme.of(context).primaryColor,
              backgroundColor: Colors.grey[800],
            ),
          ),
        ],
      ),
      actions: [
        if (_isFinished)
          Builder(
            builder: (ctx) => GlassDialogConfirmButton(
              onPressed: () => Navigator.pop(context),
            ),
          ),
      ],
    );
  }
}

class ProgramTogglesWidget extends StatefulWidget {
  final String programName;
  const ProgramTogglesWidget({super.key, required this.programName});

  @override
  State<ProgramTogglesWidget> createState() => _ProgramTogglesWidgetState();
}

class _ProgramTogglesWidgetState extends State<ProgramTogglesWidget> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: SettingsService.noFeeProgramsNotifier,
      builder: (context, noFeeList, _) {
        return ValueListenableBuilder<List<String>>(
          valueListenable: SettingsService.insuranceProgramsNotifier,
          builder: (context, insuranceList, _) {
            final isFeeApplied = !noFeeList.contains(widget.programName);
            final isInsuranceApplied = insuranceList.contains(
              widget.programName,
            );

            return Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                _buildChip(
                  label: '수수료 차감',
                  isActive: isFeeApplied,
                  onTap: () async {
                    await SettingsService.setNoFeeProgram(
                      widget.programName,
                      isFeeApplied,
                    );
                  },
                ),
                _buildChip(
                  label: '건당 보험료',
                  isActive: isInsuranceApplied,
                  onTap: () async {
                    await SettingsService.setInsuranceProgram(
                      widget.programName,
                      !isInsuranceApplied,
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? primaryColor.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? primaryColor.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? Icons.check_circle : Icons.check_circle_outline,
              size: 14,
              color: isActive ? primaryColor : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? primaryColor : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

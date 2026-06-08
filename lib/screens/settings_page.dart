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

import 'my_info_page.dart';
import 'admin_user_list_page.dart';
import '../services/auth_service.dart';
import '../config/feature_flags.dart';
import '../services/backup_service.dart';
import '../services/screenshot_auto_debug_log.dart';
import '../services/screenshot_auto_register_service.dart';
import '../services/settings_service.dart';
import '../services/shorebird_update_service.dart';
import '../services/apk_update_service.dart';
import '../utils/responsive_layout.dart';
import '../widgets/app_glass_dialog.dart';
import '../widgets/apk_update_dialog.dart';
import '../widgets/list_manage_dialog.dart';
import '../widgets/bordered_section.dart';
import '../widgets/responsive_body.dart';
import '../services/today_stats_notification_service.dart';
import 'ocr_debug_page.dart';
import '../services/db_helper.dart';
import '../utils/geocoding_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/call_point_export_service.dart';
import '../features/push_notification/widgets/admin_push_dialog.dart';
import 'notice_list_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _baseFeeCon = TextEditingController(text: SettingsService.baseFeeRate.toString());
  final _perTripInsCon = TextEditingController(text: SettingsService.perTripInsurance.toString());
  String _insuranceType = SettingsService.insuranceType;
  bool _showFloatingButtons = SettingsService.showFloatingButtons;
  bool _statusBarQuickEnabled = SettingsService.statusBarQuickEnabled;
  bool _autoBackupEnabled = SettingsService.autoBackupEnabled;
  String _imagePurgePeriod = SettingsService.imagePurgePeriod;
  bool _screenshotAutoRegisterEnabled = SettingsService.screenshotAutoRegisterEnabled;
  final _gasWebhookCon = TextEditingController(text: SettingsService.gasWebhookUrl);
  bool _hasGasChanges = false;

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
  }

  Future<void> _loadApkUpdateStatus() async {
    final hasApk = await ApkUpdateService.instance.checkForUpdate();
    if (mounted) setState(() {});
  }

  Future<void> _loadPostponedUpdateStatus() async {
    final hasPostponed = await ShorebirdUpdateService.instance.hasPostponedUpdate();
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
    final pendingStr = pending != null && pending != cur ? ' → #$pending 대기' : '';
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
    _baseFeeCon.dispose();
    _perTripInsCon.dispose();
    _versionTapTimer?.cancel();
    super.dispose();
  }

  List<Widget> _settingsSections(TextStyle versionStyle) {
    return [
      _buildListManageButton(
        title: '내 정보',
        icon: Icons.person,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyInfoPage()),
          );
        },
      ),
      _buildNoticeSection(),
      _buildBackupRestoreSettings(),
      _buildSettingsGroup(
        "수수료 설정",
        [
          _buildTextField(_baseFeeCon, "기본 수수료율 (%)", onChanged: () {
            _checkFeeChanges();
          }),
        ],
        showChangeButton: _hasFeeChanges,
        onSave: () {
          SettingsService.setBaseFeeRate(double.tryParse(_baseFeeCon.text) ?? 20.0);
          setState(() => _hasFeeChanges = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("수수료율이 저장되었습니다.")));
        },
      ),
      _buildSettingsGroup(
        "보험료 설정",
        [
          _buildRadioTile("적용 안 함", 'none'),
          _buildRadioTile(
            "건당 보험료",
            'per_trip',
            child: _insuranceType == 'per_trip'
                ? _buildTextField(_perTripInsCon, "1건당 차감 금액 (원)", onChanged: () {
                    _checkInsuranceChanges();
                  })
                : null,
          ),
        ],
        showChangeButton: _hasInsuranceChanges,
        onSave: () async {
          await SettingsService.setInsuranceType(_insuranceType);
          if (_insuranceType == 'per_trip') {
            await SettingsService.setPerTripInsurance(int.tryParse(_perTripInsCon.text) ?? 0);
          }
          setState(() => _hasInsuranceChanges = false);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("보험료 설정이 저장되었습니다.")));
        },
      ),
      _buildProgramListSettings(),
      _buildExpenseListSettings(),
      _buildIncomeListSettings(),
      if (!kIsWeb && Platform.isAndroid) _buildStatusBarQuickSettings(),
      _buildFloatingButtonSettings(),
      if (!kIsWeb && Platform.isAndroid) _buildScreenshotAutoRegisterSettings(),
      _buildCallPointShareSettings(),
      if (!kIsWeb && Platform.isAndroid) _buildOcrParseLogSettings(),
      _buildStorageSettings(),
      if (!kIsWeb && kMapFeaturesEnabled) _buildBatchGeocodeSettings(),
      if (SettingsService.isOwnerMode) _buildAdminPushSection(),
      if (kMonetizationEnabled) _buildProModeTestToggle(),
      _buildVersionInfoSection(versionStyle),
    ];
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
      final gridSections = sections.length > 1 ? sections.sublist(0, sections.length - 1) : sections;
      final versionSection = sections.isNotEmpty ? sections.last : null;
      return SingleChildScrollView(
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
                        child: i + 1 < gridSections.length ? gridSections[i + 1] : const SizedBox.shrink(),
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

    return ListView(
      padding: EdgeInsets.all(horizontalPadding),
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) SizedBox(height: groupSpacing),
          sections[i],
        ],
      ],
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
      color: Colors.white,
      fontSize: versionFs,
      fontWeight: FontWeight.w500,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F222A),
        title: Text(
          '운행 일지 설정',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFC700),
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.75),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('버전정보', style: versionStyle.copyWith(fontWeight: FontWeight.w600)),
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
      _showAdminCodeDialog();
    }
  }

  void _showAdminCodeDialog() {
    final TextEditingController codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F222A),
          title: const Text('관리자 인증', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: codeController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '인증 코드를 입력하세요',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFC700))),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final code = codeController.text.trim();
                Navigator.pop(context);
                if (code == '1234') { // TODO: 실제 사용할 어드민 코드로 변경
                  final isAdmin = AuthService.instance.userDoc?['isAdmin'] == true;
                  if (isAdmin) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AdminUserListPage()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('접근 권한이 없는 계정입니다.')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('코드가 일치하지 않습니다.')),
                  );
                }
              },
              child: const Text('확인', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> children, {bool showChangeButton = false, VoidCallback? onSave}) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold)),
              if (showChangeButton && onSave != null)
                ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("변경", style: TextStyle(fontWeight: FontWeight.bold)),
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
    Color titleColor = Colors.white,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFFFFC700)),
      title: Text(title, style: TextStyle(color: titleColor, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF6E717C), size: 16),
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
          title: Text(title, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
          value: value,
          groupValue: _insuranceType,
          activeColor: const Color(0xFFFFC700),
          onChanged: (v) {
            setState(() {
              _insuranceType = v!;
            });
            _checkInsuranceChanges();
          },
        ),
        if (child != null) Padding(padding: EdgeInsets.only(left: leftPadding, bottom: bottomPadding), child: child),
      ],
    );
  }

  Widget _buildTextField(TextEditingController con, String label, {VoidCallback? onChanged}) {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final borderRadius = isTablet ? 16.0 : 12.0;
    final horizontalPadding = isTablet ? 20.0 : 16.0;
    final verticalPadding = isTablet ? 16.0 : 12.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF16181D), borderRadius: BorderRadius.circular(borderRadius)),
      child: TextField(
        controller: con, 
        keyboardType: TextInputType.number,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
        decoration: InputDecoration(
          labelText: label, 
          labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          floatingLabelStyle: const TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
          border: InputBorder.none, 
          contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
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
        onAdd: (item) async {
          final list = List<String>.from(SettingsService.programList)..add(item);
          await SettingsService.setProgramList(list);
          return true;
        },
        onDelete: (_, item) async {
          final list = List<String>.from(SettingsService.programList)..remove(item);
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

  Widget _buildListManageButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color accentColor = const Color(0xFFFFC700),
  }) {
    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: accentColor, size: 22),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  Widget _buildScreenshotAutoRegisterSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '스크린샷 일지 자동저장',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('자동 저장 사용', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            value: _screenshotAutoRegisterEnabled,
            activeThumbColor: const Color(0xFFFFC700),
            onChanged: (value) async {
              if (value && !SettingsService.isFeatureUnlocked()) {
                _showAdRewardDialog(context, () async {
                  final status = await Permission.notification.request();
                  if (!status.isGranted) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('알림 권한이 필요합니다. 허용해야 백그라운드 감지 알림이 표시됩니다.'),
                      ),
                    );
                    return;
                  }
                  await SettingsService.setScreenshotAutoRegisterEnabled(true);
                  await ScreenshotAutoRegisterService.instance.syncWithSettingsPreference();
                  if (!mounted) return;
                  setState(() {
                    _screenshotAutoRegisterEnabled = SettingsService.screenshotAutoRegisterEnabled;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('스크린샷 자동저장이 켜졌습니다.')),
                  );
                });
                return;
              }

              if (value) {
                final status = await Permission.notification.request();
                if (!status.isGranted) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('알림 권한이 필요합니다. 허용해야 백그라운드 감지 알림이 표시됩니다.'),
                    ),
                  );
                  return;
                }
              }
              await SettingsService.setScreenshotAutoRegisterEnabled(value);
              await ScreenshotAutoRegisterService.instance.syncWithSettingsPreference();
              if (!mounted) return;
              setState(() {
                _screenshotAutoRegisterEnabled = SettingsService.screenshotAutoRegisterEnabled;
              });
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(value ? '스크린샷 자동저장이 켜졌습니다.' : '스크린샷 자동저장이 꺼졌습니다.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOcrParseLogSettings() {
    return _buildSettingsGroup(
      '디버그 및 로그',
      [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long, color: Color(0xFFFFC700)),
          title: const Text('콜카드 인식 로그', style: TextStyle(color: Colors.white, fontSize: 16)),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF6E717C), size: 16),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OcrDebugPage()));
          },
        ),
      ],
    );
  }

  void _showBackupOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F222A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('백업 위치 선택', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.phone_android, color: Color(0xFFFFC700)),
                title: const Text('단말기 (Downloads) 저장', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.backupToLocalDevice(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Color(0xFF2196F3)),
                title: const Text('구글 드라이브 등 공유 저장', style: TextStyle(color: Colors.white)),
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
      backgroundColor: const Color(0xFF1F222A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('복원 위치 선택', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.phone_android, color: Color(0xFFFFC700)),
                title: const Text('단말기에서 가져오기', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.restoreFromFilePicker(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download, color: Color(0xFF2196F3)),
                title: const Text('구글 드라이브에서 가져오기', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.restoreFromFilePicker(context);
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("데이터 백업/복원", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showBackupOptions();
                  },
                  icon: const Icon(Icons.cloud_upload, color: Colors.white),
                  label: const Text("백업"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showRestoreOptions();
                  },
                  icon: const Icon(Icons.cloud_download, color: Colors.white),
                  label: const Text("복원"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF2C2F38), height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("7일 주기 자동 백업 (ZIP)", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: Text(
              "최근 자동 백업일: $displayDate",
              style: const TextStyle(color: Color(0xFF6E717C), fontSize: 12),
            ),
            value: _autoBackupEnabled,
            activeThumbColor: const Color(0xFFFFC700),
            activeColor: const Color(0xFFFFC700).withOpacity(0.3),
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("콜포인트(좌표) 공유", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await CallPointExportService.exportToCsv(context);
                  },
                  icon: const Icon(Icons.share, color: Colors.white),
                  label: const Text("내보내기"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await CallPointExportService.importFromCsv(context);
                  },
                  icon: const Icon(Icons.download, color: Colors.white),
                  label: const Text("가져오기"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("데이터 정리", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: spacing),
          DropdownButtonFormField<String>(
            value: _imagePurgePeriod,
            dropdownColor: const Color(0xFF1F222A),
            decoration: const InputDecoration(
              labelText: "오래된 콜카드 이미지 정리 기준",
              labelStyle: TextStyle(color: Color(0xFF6E717C), fontSize: 13),
              floatingLabelStyle: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
              border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2C2F38))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2C2F38))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFC700))),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            items: const [
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
                      Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx, false))),
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
              icon: const Icon(Icons.cleaning_services_outlined, color: Colors.black),
              label: const Text("이미지 정리"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(vertical: isTablet ? 14 : 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBarQuickSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "상태바 퀵기능",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("고정 알림 (오늘 순익)", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            value: _statusBarQuickEnabled,
            activeThumbColor: const Color(0xFFFFC700),
            onChanged: (value) async {
              if (value && !SettingsService.isFeatureUnlocked()) {
                _showAdRewardDialog(context, () async {
                  final status = await Permission.notification.request();
                  if (!status.isGranted) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("알림 권한이 필요합니다. 설정에서 허용해 주세요.")),
                    );
                    return;
                  }
                  await SettingsService.setStatusBarQuickEnabled(true);
                  await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
                  if (!mounted) return;
                  setState(() => _statusBarQuickEnabled = SettingsService.statusBarQuickEnabled);
                });
                return;
              }

              if (value) {
                final status = await Permission.notification.request();
                if (!status.isGranted) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("알림 권한이 필요합니다. 설정에서 허용해 주세요.")),
                  );
                  return;
                }
                await SettingsService.setStatusBarQuickEnabled(true);
                await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
              } else {
                await SettingsService.setStatusBarQuickEnabled(false);
                await TodayStatsNotificationService.instance.cancel();
              }
              if (!mounted) return;
              setState(() => _statusBarQuickEnabled = SettingsService.statusBarQuickEnabled);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButtonSettings() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("화면 설정", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold)),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("폰트 크기 조절 버튼", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            value: _showFloatingButtons,
            activeThumbColor: const Color(0xFFFFC700),
            onChanged: (value) {
              setState(() {
                _showFloatingButtons = value;
              });
              SettingsService.setShowFloatingButtons(value);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _runBatchGeocodeUpdate() async {
    final db = await DriveLogDatabase.instance.database;
    final logs = await db.query(
      'drive_logs',
      where: 'start_lat IS NULL OR start_lng IS NULL OR end_lat IS NULL OR end_lng IS NULL',
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
          decoration: BorderedSection.decoration(borderRadius: 12),
          child: ListTile(
            title: const Text('👑 [TEST] PRO 모드 (무료/유료 전환)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text('개발자 테스트용 강제 전환 스위치', style: TextStyle(color: Colors.white70, fontSize: 12)),
            trailing: Switch(
              value: isPremium,
              activeColor: const Color(0xFFFFC700),
              onChanged: (value) async {
                await SettingsService.setIsPremiumUser(value);
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFC700),
                side: const BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.campaign_rounded, size: 20),
              label: const Text('공지사항 푸시 발송 (관리자)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _openAdminPushDialog(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFC700),
                side: const BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.person, size: 20),
              label: const Text('회원 관리 (관리자)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminUserListPage()),
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFC700),
                side: const BorderSide(color: Color(0xFFFFC700)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  const Icon(Icons.notifications, size: 20),
                  const SizedBox(width: 8),
                  const Text('알림목록', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_unreadNoticeCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_unreadNoticeCount',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                backgroundColor: const Color(0xFF1F222A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                if (ApkUpdateService.instance.hasApkUpdate) {
                  ApkUpdateDialog.show(
                    context, 
                    ApkUpdateService.instance.downloadUrl ?? 'https://dbros-install.web.app/'
                  );
                } else if (_hasPostponedUpdate) {
                  // Show the custom popup with Apply Patch and APK Download
                  showDialog(
                    context: context,
                    builder: (ctx) => Dialog(
                      backgroundColor: const Color(0xFF1F222A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '업데이트 선택',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFC700),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      final result = await ShorebirdUpdateService.instance.checkAndUpdate();
                                      if (!result && mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('현재 최신 버전을 사용 중입니다.')),
                                        );
                                      }
                                    },
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.center,
                                      children: [
                                        const Text('패치적용', style: TextStyle(fontWeight: FontWeight.bold)),
                                        Positioned(
                                          top: -8,
                                          right: -12,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white24),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () async {
                                      Navigator.of(ctx).pop();
                                      final url = Uri.parse('https://dbros-install.web.app/');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: const Text('APK다운', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  // Direct patch check if no badge
                  final result = await ShorebirdUpdateService.instance.checkAndUpdate();
                  if (!result && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('현재 최신 버전을 사용 중입니다.')),
                    );
                  }
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download, size: 20),
                      SizedBox(width: 8),
                      Text('업데이트', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (_hasPostponedUpdate || ApkUpdateService.instance.hasApkUpdate)
                    Positioned(
                      top: 2,
                      right: 4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
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
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "과거 데이터 좌표 일괄 업데이트",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          Text(
            '과거에 등록되어 좌표가 비어있는 운행일지 데이터들을 추려, 주소를 좌표로 자동 변환하여 채워 넣습니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _runBatchGeocodeUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.pin_drop),
              label: const Text('좌표 일괄 업데이트 시작', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdRewardDialog(BuildContext context, VoidCallback onSuccess) async {
    final confirm = await AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.ondemand_video,
        title: '기능 일시 잠금 해제',
        content: '30초 광고를 시청하시면 3시간 동안 해당 기능을 무료로 이용하실 수 있습니다.\n\n광고를 시청하시겠습니까?',
        actions: [
          Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx, false), label: '취소')),
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
      // TODO: 실제 리워드 광고 연동 (google_mobile_ads)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1F222A),
          content: Row(
            children: const [
              CircularProgressIndicator(color: Color(0xFFFFC700)),
              SizedBox(width: 16),
              Text('광고 시청 중... (테스트)', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (!context.mounted) return;
      Navigator.pop(context); // 닫기

      await SettingsService.unlockFeaturesByAd();
      onSuccess();
    }
  }
}

/// 좌표 일괄 업데이트 진행 다이얼로그 (진행 상태는 State에 보관).
class _BatchGeocodeProgressDialog extends StatefulWidget {
  const _BatchGeocodeProgressDialog({required this.logs});

  final List<Map<String, dynamic>> logs;

  @override
  State<_BatchGeocodeProgressDialog> createState() => _BatchGeocodeProgressDialogState();
}

class _BatchGeocodeProgressDialogState extends State<_BatchGeocodeProgressDialog> {
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
        final loc = await GeocodingUtils.getCoordinateFromAddressFallback(startLoc);
        if (loc != null) {
          updateData['start_lat'] = loc.latitude;
          updateData['start_lng'] = loc.longitude;
        }
      }

      if (log['end_lat'] == null && endLoc.isNotEmpty) {
        final loc = await GeocodingUtils.getCoordinateFromAddressFallback(endLoc);
        if (loc != null) {
          updateData['end_lat'] = loc.latitude;
          updateData['end_lng'] = loc.longitude;
        }
      }

      if (updateData.isNotEmpty) {
        await db.update('drive_logs', updateData, where: 'id = ?', whereArgs: [log['id']]);
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
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _isFinished ? '좌표 반영 $_updated건' : '주소를 좌표로 변환하는 중입니다…',
            style: const TextStyle(color: Color(0xFF9FA3AE), fontSize: 13),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _isFinished ? 1.0 : progress,
              minHeight: 8,
              color: const Color(0xFFFFC700),
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
import 'dart:io' show Platform;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/feature_flags.dart';
import '../services/backup_service.dart';
import '../services/screenshot_auto_debug_log.dart';
import '../services/screenshot_auto_register_service.dart';
import '../services/settings_service.dart';
import '../utils/responsive_layout.dart';
import '../widgets/bordered_section.dart';
import '../widgets/responsive_body.dart';
import '../services/today_stats_notification_service.dart';
import 'ocr_debug_page.dart';
import '../services/db_helper.dart';
import '../utils/geocoding_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/call_point_export_service.dart';
import '../features/push_notification/widgets/admin_push_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _baseFeeCon = TextEditingController(text: SettingsService.baseFeeRate.toString());
  final _perTripInsCon = TextEditingController(text: SettingsService.perTripInsurance.toString());
  String _insuranceType = SettingsService.insuranceType;
  final List<String> _programList = List.from(SettingsService.programList);
  final _newProgramCon = TextEditingController();
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

  bool _showAddProgram = false;
  bool _showDeleteProgram = false;

  String _appVersionLabel = '';
  
  int _versionTapCount = 0;
  DateTime? _lastVersionTapTime;

  @override
  void initState() {
    super.initState();
    _loadAppVersionLabel();
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
    _newProgramCon.dispose();
    super.dispose();
  }

  List<Widget> _settingsSections(TextStyle versionStyle) {
    return [
      _buildBackupRestoreSettings(),
      _buildSettingsGroup(
        "수수료 설정",
        [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '카카오·티맵·핸들포유에는 아래 수수료율이 적용되지 않습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A8D96)),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '「건당 보험료」는 카카오(제휴), 로지, 콜마너, 핸들포유, 기타에만 1건당 설정금액이 차감됩니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A8D96)),
            ),
          ),
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
      if (!kIsWeb && Platform.isAndroid) _buildStatusBarQuickSettings(),
      _buildFloatingButtonSettings(),
      _buildCallPointShareSettings(),
      if (!kIsWeb && Platform.isAndroid) _buildScreenshotAutoRegisterSettings(),
      _buildStorageSettings(),
      if (!kIsWeb && kMapFeaturesEnabled) _buildBatchGeocodeSettings(),
      if (!kIsWeb && kMapFeaturesEnabled) _buildAdminPushSection(),
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
      child: Row(
        children: [
          Text('버전정보', style: versionStyle.copyWith(fontWeight: FontWeight.w600)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _handleVersionTap,
                child: Container(
                  color: Colors.transparent, // 터치 영역 확보
                  padding: const EdgeInsets.all(4.0),
                  child: Text(label, style: versionStyle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleVersionTap() {
    final now = DateTime.now();
    if (_lastVersionTapTime == null || now.difference(_lastVersionTapTime!).inSeconds > 2) {
      _versionTapCount = 1;
    } else {
      _versionTapCount++;
    }
    _lastVersionTapTime = now;

    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      _showOwnerModeDialog();
    }
  }

  void _showOwnerModeDialog() {
    if (true || SettingsService.isOwnerMode) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1F222A),
          title: const Text('오너 모드 해제', style: TextStyle(color: Colors.white)),
          content: const Text('오너 모드를 해제하고 퍼블릭 모드로 전환하시겠습니까?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                await SettingsService.setIsOwnerMode(false);
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('퍼블릭 모드로 전환되었습니다.')),
                );
              },
              child: const Text('해제', style: TextStyle(color: Color(0xFFFF5252))),
            ),
          ],
        ),
      );
    } else {
      final codeCon = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1F222A),
          title: const Text('마스터 코드 입력', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: codeCon,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '코드를 입력하세요',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFC700))),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final input = codeCon.text.trim();
                final bytes = utf8.encode(input);
                final digest = sha256.convert(bytes).toString().toLowerCase();
                // "HYM" 의 SHA-256 해시값
                final targetHash = '8bd584776a2317022906d3da03e66184ddee9d979bb3fde82af39748c3cae422'; 
                
                if (digest == targetHash) {
                  await SettingsService.setIsOwnerMode(true);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('오너 모드가 활성화되었습니다.')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('코드가 일치하지 않습니다.')),
                  );
                }
              },
              child: const Text('인증', style: TextStyle(color: Color(0xFFFFC700))),
            ),
          ],
        ),
      );
    }
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
          Text("프로그램 목록관리", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      if (_showAddProgram) {
                        _showAddProgram = false;
                        _newProgramCon.clear();
                      } else {
                        _showAddProgram = true;
                        _showDeleteProgram = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text("추가"),
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
                    setState(() {
                      if (_showDeleteProgram) {
                        _showDeleteProgram = false;
                      } else {
                        _showDeleteProgram = true;
                        _showAddProgram = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.delete, color: Colors.white),
                  label: const Text("삭제"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
                  ),
                ),
              ),
            ],
          ),
          if (_showAddProgram) ...[
            SizedBox(height: spacing),
            _buildAddProgramField(),
          ],
          if (_showDeleteProgram) ...[
            SizedBox(height: spacing),
            _buildProgramList(),
          ],
        ],
      ),
    );
  }

  Widget _buildProgramList() {
    return Column(
      children: _programList.asMap().entries.map((entry) {
        final index = entry.key;
        final program = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF16181D),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: Text(program, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
            trailing: _showDeleteProgram ? IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: () {
                setState(() {
                  _programList.removeAt(index);
                });
                SettingsService.setProgramList(_programList);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$program 프로그램이 삭제되었습니다.")),
                );
              },
            ) : null,
          ),
        );
      }).toList(),
    );
  }
  Widget _buildAddProgramField() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final borderRadius = isTablet ? 16.0 : 12.0;
    final horizontalPadding = isTablet ? 20.0 : 16.0;
    final verticalPadding = isTablet ? 16.0 : 12.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF16181D), borderRadius: BorderRadius.circular(borderRadius)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _newProgramCon,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
              decoration: InputDecoration(
                labelText: "새 프로그램 추가",
                labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
                floatingLabelStyle: const TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final newProgram = _newProgramCon.text.trim();
              if (newProgram.isNotEmpty && !_programList.contains(newProgram)) {
                setState(() {
                  _programList.add(newProgram);
                  _newProgramCon.clear();
                  _showAddProgram = false;
                });
                SettingsService.setProgramList(_programList);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$newProgram 프로그램이 추가되었습니다.")),
                );
              } else if (newProgram.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("프로그램 이름을 입력해주세요.")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("이미 존재하는 프로그램입니다.")),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
            '스크린샷 자동저장',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('자동 저장 사용', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            subtitle: Text(
              '켜두면 스크린샷 직후 콜카드로 인식될 때만 운행일지에 자동 등록합니다. 끄면 감시 리스너가 해제되어 동작하지 않습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
            ),
            value: _screenshotAutoRegisterEnabled,
            activeThumbColor: const Color(0xFFFFC700),
            onChanged: (value) async {
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

  Widget _buildScreenshotAutoDiagSettings() {
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
            '스크린샷 자동등록 진단',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showScreenshotAutoDiagDialog(),
              icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
              label: const Text('진단 로그 보기 (최근 기록)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
              ),
            ),
          ),
          SizedBox(height: spacing),
          Text(
            '• 캡처 후에도 반응이 없을 때: 위 버튼으로 앱 안에서만 확인합니다(adb 불필요).\n'
            '• 최대 약 150줄까지 메모리에 유지됩니다. 앱을 완전히 종료하면 비워질 수 있습니다.\n'
            '• 이벤트가 한 줄도 없으면 MediaStore/플러그인에서 변화가 오지 않은 것입니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
        ],
      ),
    );
  }

  void _showScreenshotAutoDiagDialog() {
    final text = ScreenshotAutoDebugLog.newestFirstText();
    final body = text.isEmpty ? '(아직 기록 없음 — 앱 실행 후 캡처를 한 번 시도해 보세요.)' : text;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        title: const Text('스크린샷 자동등록 진단', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: SingleChildScrollView(
            child: SelectableText(
              body,
              style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 12,
                height: 1.35,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: body));
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('진단 로그를 클립보드에 복사했습니다.')),
              );
            },
            child: const Text('복사 후 닫기', style: TextStyle(color: Color(0xFFFFC700))),
          ),
          TextButton(
            onPressed: () {
              ScreenshotAutoDebugLog.clear();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('진단 로그를 비웠습니다.')),
              );
            },
            child: const Text('비우기', style: TextStyle(color: Color(0xFFFF5252))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrParseLogSettings() {
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
          Text(
            "콜카드 인식 로그",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OcrDebugPage()),
                );
              },
              icon: const Icon(Icons.bug_report_outlined, color: Colors.white),
              label: const Text("로그추출"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9C27B0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
              ),
            ),
          ),
          SizedBox(height: spacing),
          Text(
            "• 콜카드 인식 시 인식결과가 누적됩니다.\n• 로그추출 화면을 통해 전체 인식로그 조회 및 복사,공유가 가능합니다.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
        ],
      ),
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
                subtitle: const Text('단말기 내 다운로드 폴더에 즉시 저장합니다.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.backupToLocalDevice(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Color(0xFF2196F3)),
                title: const Text('구글 드라이브 등 공유 저장', style: TextStyle(color: Colors.white)),
                subtitle: const Text('공유 창을 열어 드라이브 앱으로 내보냅니다.', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                subtitle: const Text('단말기 내의 백업 폴더에서 파일을 선택합니다.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  BackupService.restoreFromFilePicker(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download, color: Color(0xFF2196F3)),
                title: const Text('구글 드라이브에서 가져오기', style: TextStyle(color: Colors.white)),
                subtitle: const Text('좌측 메뉴에서 Google Drive를 선택해주세요.', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
    final borderRadius = isTablet ? 24.0 : 20.0;

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
          SizedBox(height: spacing),
          Text(
            "• 백업 : 백업파일(DB/이미지)를 내부저장소에 저장합니다.\n• 복원 : 저장해둔 백업파일(.zip)을 선택해 데이터를 불러옵니다.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
          const Divider(color: Color(0xFF2C2F38), height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("7일 주기 자동 백업 (ZIP)", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: Text(
              "최근 자동 백업일: $displayDate\n매 7일 경과 후 앱 실행 시 단말기 'Downloads' 폴더에 이미지와 DB가 패키징된 ZIP 파일로 백업됩니다.",
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
          SizedBox(height: spacing),
          Text(
            "• 내보내기 : 내 앱에 저장된 콜포인트를 CSV 파일로 추출하여 공유합니다.\n• 가져오기 : 다른 사람이 공유한 콜포인트 CSV 파일을 내 지도에 추가합니다.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageSettings() {
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
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1F222A),
                    title: const Text("이미지 정리", style: TextStyle(color: Colors.white, fontFamily: 'GmarketSans', fontWeight: FontWeight.w700)),
                    content: Text(
                      _imagePurgePeriod == 'none'
                          ? "설정된 정리 기준이 없습니다. 정리 기준을 '3개월 이전' 또는 '6개월 이전'으로 선택한 뒤 다시 시도해 주세요."
                          : "선택한 이미지 정리 기준(${_imagePurgePeriod == '3_months' ? '3개월' : '6개월'} 이전)에 따라 오래된 원본 이미지를 디스크에서 제거하시겠습니까?\n\n※ 정산 및 운행일지 기록은 그대로 보존됩니다.",
                      style: const TextStyle(color: Color(0xFF8A8D96)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("취소", style: TextStyle(color: Color(0xFF6E717C))),
                      ),
                      if (_imagePurgePeriod != 'none')
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text("지금 정리", style: TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold)),
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
          SizedBox(height: spacing * 0.5),
          Text(
            "• 이미지 정리는 일지 작성때 인식한 이미지파일만 제거하여 여유 공간을 확보합니다.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBarQuickSettings() {
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
          Text(
            "상태바 퀵기능",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("고정 알림 (오늘 순익)", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            subtitle: Text(
              "알림 패널에 오늘 순익을 표시합니다.\n일지 등록·수정 시 갱신됩니다.\n"
              "본문 탭: 일반 작성 화면 · ⚡ 퀵등록: 반투명 퀵 입력.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
            ),
            value: _statusBarQuickEnabled,
            activeThumbColor: const Color(0xFFFFC700),
            onChanged: (value) async {
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
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("화면 설정", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("폰트 크기 조절 버튼", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            subtitle: Text("우측 하단에 폰트 크기 조절 버튼 표시", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C))),
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

  Widget _buildAdminPushSection() {
    final isTablet = ResponsiveLayout.isFoldOrTablet(context);
    final padding = isTablet ? 20.0 : 16.0;

    return Container(
      decoration: BorderedSection.decoration(borderRadius: 12),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '마스터 전용 기능',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '전체 사용자에게 FCM 푸시 알림을 발송합니다.\nFirestore → Cloud Functions → FCM 경로로 처리됩니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6E717C),
                ),
          ),
          const SizedBox(height: 14),
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
              label: const Text('공지사항 푸시 발송',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _openAdminPushDialog(),
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
            '과거에 등록되어 좌표가 비어있는 운행일지 데이터들을 추려, 주소를 좌표로 자동 변환하여 채워 넣습니다.\n(구글 지오코더를 이용하며 과금되지 않습니다.)',
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

    return AlertDialog(
      backgroundColor: const Color(0xFF1F222A),
      title: Text(
        _isFinished ? '좌표 일괄 업데이트 완료' : '좌표 일괄 업데이트 중',
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: Column(
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인', style: TextStyle(color: Color(0xFFFFC700))),
          ),
      ],
    );
  }
}
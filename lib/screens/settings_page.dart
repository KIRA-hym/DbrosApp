import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/backup_service.dart';
import '../services/ocr_parse_log_service.dart';
import '../services/settings_service.dart';
import '../services/today_stats_notification_service.dart';
import 'ocr_debug_page.dart';

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

  final double _initialBaseFeeRate = SettingsService.baseFeeRate;
  final String _initialInsuranceType = SettingsService.insuranceType;
  final int _initialPerTripInsurance = SettingsService.perTripInsurance;

  bool _hasFeeChanges = false;
  bool _hasInsuranceChanges = false;

  bool _showAddProgram = false;
  bool _showDeleteProgram = false;

  String _appVersionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersionLabel();
  }

  Future<void> _loadAppVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = 'v${info.version}.${info.buildNumber}';
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final horizontalPadding = isTablet ? 24.0 : 20.0;
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
        title: Text("운행 일지 설정", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: const Color(0xFFFFC700))),
      ),
      body: ListView(
        padding: EdgeInsets.all(horizontalPadding),
        children: [
          _buildBackupRestoreSettings(),
          SizedBox(height: groupSpacing),
          _buildOcrParseLogSettings(),
          SizedBox(height: groupSpacing),
          _buildSettingsGroup("수수료 설정", [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '카카오 전 항목·티맵·핸들포유에는 아래 수수료율이 적용되지 않습니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A8D96)),
              ),
            ),
            _buildTextField(_baseFeeCon, "기본 수수료율 (%)", onChanged: () {
              _checkFeeChanges();
            }),
          ], showChangeButton: _hasFeeChanges, onSave: () {
            SettingsService.setBaseFeeRate(double.tryParse(_baseFeeCon.text) ?? 20.0);
            setState(() => _hasFeeChanges = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("수수료율이 저장되었습니다.")));
          }),
          SizedBox(height: groupSpacing),
          _buildSettingsGroup("보험료 설정", [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '「건당 보험료」는 카카오(제휴), 로지, 콜마너, 핸들포유, 기타에만 1건당 금액이 더해집니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF8A8D96)),
              ),
            ),
            _buildRadioTile("적용 안 함", 'none'),
            _buildRadioTile("건당 보험료", 'per_trip', child: _insuranceType == 'per_trip' ? _buildTextField(_perTripInsCon, "1건당 차감 금액 (원)", onChanged: () {
              _checkInsuranceChanges();
            }) : null),
          ], showChangeButton: _hasInsuranceChanges, onSave: () async {
            await SettingsService.setInsuranceType(_insuranceType);
            if (_insuranceType == 'per_trip') {
              await SettingsService.setPerTripInsurance(int.tryParse(_perTripInsCon.text) ?? 0);
            }
            setState(() => _hasInsuranceChanges = false);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("보험료 설정이 저장되었습니다.")));
          }),
          SizedBox(height: groupSpacing),
          _buildProgramListSettings(),
          SizedBox(height: groupSpacing),
          if (!kIsWeb && Platform.isAndroid) ...[
            _buildStatusBarQuickSettings(),
            SizedBox(height: groupSpacing),
          ],
          _buildFloatingButtonSettings(),
          SizedBox(height: groupSpacing),
          _buildVersionInfoSection(versionStyle),
        ],
      ),
    );
  }

  Widget _buildVersionInfoSection(TextStyle versionStyle) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;
    final label = _appVersionLabel.isEmpty ? '…' : _appVersionLabel;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F222A),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.75),
      child: Row(
        children: [
          Text('버전정보', style: versionStyle.copyWith(fontWeight: FontWeight.w600)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(label, style: versionStyle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> children, {bool showChangeButton = false, VoidCallback? onSave}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(borderRadius)),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(borderRadius)),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("프로그램 목록 관리", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
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

  Widget _buildOcrParseLogSettings() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(borderRadius)),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "OCR 파싱 로그",
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
              label: const Text("OCR 디버그 (로그 추출)"),
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
            "• OCR 인식 시 파싱 결과가 앱 내부에 누적됩니다\n• OCR 디버그 화면을 통해 전체 파싱 로그 조회 및 클립보드 복사, 공유/추출이 가능합니다",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupRestoreSettings() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(borderRadius)),
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
                  onPressed: () async {
                    await BackupService.backupToSelectedFile(context);
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
                  onPressed: () async {
                    await BackupService.restoreFromSelectedFile(context);
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
            "• 백업: 백업 파일(.json)을 원하는 위치(기기/클라우드)에 저장합니다\n• 복원: 저장해둔 백업 파일(.json)을 선택해 데이터를 불러옵니다",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBarQuickSettings() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(borderRadius)),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "상태바·퀵 기능",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("고정 알림 (오늘 순익)", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            subtitle: Text(
              "알림 패널에 오늘 순익을 표시합니다. 일지 등록·수정 시 갱신됩니다.\n"
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final padding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 20.0 : 16.0;
    final borderRadius = isTablet ? 24.0 : 20.0;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F222A), borderRadius: BorderRadius.circular(borderRadius)),
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
}
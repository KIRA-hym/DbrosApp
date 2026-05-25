import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/backup_service.dart';
import '../services/expense_repository.dart';
import '../services/settings_service.dart';
import '../utils/responsive_layout.dart';
import '../widgets/responsive_body.dart';

class ExpenseSettingsPage extends StatefulWidget {
  const ExpenseSettingsPage({super.key});

  @override
  State<ExpenseSettingsPage> createState() => _ExpenseSettingsPageState();
}

class _ExpenseSettingsPageState extends State<ExpenseSettingsPage> {
  final List<Map<String, dynamic>> _categories = [];
  final _newCatCon = TextEditingController();
  bool _showAdd = false;
  bool _showDelete = false;
  bool _showFloatingButtons = SettingsService.showFloatingButtons;
  String _appVersionLabel = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadAppVersionLabel();
  }

  Future<void> _loadCategories() async {
    final rows = await ExpenseRepository.getCategories();
    if (!mounted) return;
    setState(() {
      _categories
        ..clear()
        ..addAll(rows);
      _loading = false;
    });
  }

  Future<void> _loadAppVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersionLabel =
          'v${info.version}.${info.buildNumber.padLeft(2, '0')}');
    } catch (_) {
      if (mounted) setState(() => _appVersionLabel = '');
    }
  }

  @override
  void dispose() {
    _newCatCon.dispose();
    super.dispose();
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
        title: Text(
          '지출 설정',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: const Color(0xFFFFC700)),
        ),
      ),
      body: ResponsiveBody(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700)))
            : ListView(
              padding: EdgeInsets.all(horizontalPadding),
              children: [
                _buildBackupRestore(),
                SizedBox(height: groupSpacing),
                _buildCategorySection(),
                SizedBox(height: groupSpacing),
                _buildFloatingSection(),
                SizedBox(height: groupSpacing),
                _buildVersionSection(versionStyle),
              ],
            ),
      ),
    );
  }

  Widget _buildVersionSection(TextStyle versionStyle) {
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

  Widget _buildBackupRestore() {
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
            '데이터 백업/복원',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showBackupOptions();
                  },
                  icon: const Icon(Icons.cloud_upload, color: Colors.white),
                  label: const Text('백업'),
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
                  label: const Text('복원'),
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
            '• 운행일지·지출 설정 어디서 백업하든 동일 파일에 두 데이터가 포함됩니다.\n• 복원 시 운행일지와 지출이 함께 반영됩니다.',
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
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await BackupService.restoreFromFilePicker(context);
                  if (ok && mounted) await _loadCategories();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download, color: Color(0xFF2196F3)),
                title: const Text('구글 드라이브에서 가져오기', style: TextStyle(color: Colors.white)),
                subtitle: const Text('좌측 메뉴에서 Google Drive를 선택해주세요.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await BackupService.restoreFromFilePicker(context);
                  if (ok && mounted) await _loadCategories();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
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
            '지출항목 관리',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      if (_showAdd) {
                        _showAdd = false;
                        _newCatCon.clear();
                      } else {
                        _showAdd = true;
                        _showDelete = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('추가'),
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
                      if (_showDelete) {
                        _showDelete = false;
                      } else {
                        _showDelete = true;
                        _showAdd = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.delete, color: Colors.white),
                  label: const Text('삭제'),
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
          if (_showAdd) ...[
            SizedBox(height: spacing),
            Container(
              decoration: BoxDecoration(color: const Color(0xFF16181D), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newCatCon,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: '새 지출 항목',
                        labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
                        floatingLabelStyle: const TextStyle(color: Color(0xFFFFC700), fontWeight: FontWeight.bold),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 16 : 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final t = _newCatCon.text.trim();
                      if (t.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('항목 이름을 입력해 주세요.')));
                        return;
                      }
                      await ExpenseRepository.addCategory(t);
                      if (!mounted) return;
                      _newCatCon.clear();
                      setState(() => _showAdd = false);
                      await _loadCategories();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$t 항목이 추가되었습니다.')));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC700),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
          if (_showDelete) ...[
            SizedBox(height: spacing),
            ..._categories.map((row) {
              final name = row['name']?.toString() ?? '';
              final id = (row['id'] as num?)?.toInt() ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF16181D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () async {
                      await ExpenseRepository.deleteCategory(id);
                      if (!mounted) return;
                      await _loadCategories();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name 항목이 삭제되었습니다.')));
                    },
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFloatingSection() {
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
            '화면 설정',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: spacing),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('폰트 크기 조절 버튼', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
            subtitle: Text(
              '우측 하단에 폰트 크기 조절 버튼 표시',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6E717C)),
            ),
            value: _showFloatingButtons,
            activeThumbColor: const Color(0xFFFFC700),
            onChanged: (value) {
              setState(() => _showFloatingButtons = value);
              SettingsService.setShowFloatingButtons(value);
            },
          ),
        ],
      ),
    );
  }
}

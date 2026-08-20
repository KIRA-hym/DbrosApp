import 'dart:io';

void main() {
  final file = File('lib/screens/settings_page.dart');
  String code = file.readAsStringSync();

  if (!code.contains("import '../services/overlay_manager.dart';")) {
    code = code.replaceFirst(
        "import '../services/settings_service.dart';", 
        "import '../services/settings_service.dart';\nimport '../services/overlay_manager.dart';");
  }

  // 1. Add _showFeeInsuranceDialog inside _SettingsPageState
  if (!code.contains('_showFeeInsuranceDialog')) {
    final dialogCode = """
  void _showFeeInsuranceDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color,
              title: Text("수수료 및 보험료 설정", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("기본 수수료율 (%)", style: TextStyle(color: Colors.white, fontSize: 14)),
                    SizedBox(height: 8),
                    TextField(
                      controller: _baseFeeCon,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Color(0xFF2C2F3D),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    SizedBox(height: 24),
                    Text("보험료 설정", style: TextStyle(color: Colors.white, fontSize: 14)),
                    RadioListTile<String>(
                      title: Text("적용 안 함", style: TextStyle(color: Colors.white)),
                      value: 'none',
                      groupValue: _insuranceType,
                      activeColor: Theme.of(context).primaryColor,
                      onChanged: (val) {
                        setDialogState(() => _insuranceType = val!);
                        setState(() => _insuranceType = val!);
                      },
                    ),
                    RadioListTile<String>(
                      title: Text("건당 보험료", style: TextStyle(color: Colors.white)),
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
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                        child: TextField(
                          controller: _perTripInsCon,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "1건당 차감 금액 (원)",
                            labelStyle: TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Color(0xFF2C2F3D),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("취소", style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () async {
                    await SettingsService.setBaseFeeRate(double.tryParse(_baseFeeCon.text) ?? 20.0);
                    await SettingsService.setInsuranceType(_insuranceType);
                    await SettingsService.setPerTripInsurance(int.tryParse(_perTripInsCon.text) ?? 0);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("수수료 및 보험료가 저장되었습니다.")));
                    }
                  },
                  child: Text("저장", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
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
            title: Text("고정 알림 상태바", style: TextStyle(color: Colors.white)),
            subtitle: Text("알림 패널에 오늘 순익 표시", style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _statusBarQuickEnabled,
            activeThumbColor: Theme.of(context).primaryColor,
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
                  setState(() => _statusBarQuickEnabled = true);
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
              }

              await SettingsService.setStatusBarQuickEnabled(value);
              if (value) {
                await TodayStatsNotificationService.instance.refreshFromDbIfEnabled();
              } else {
                await TodayStatsNotificationService.instance.cancelNotification();
              }

              if (!mounted) return;
              setState(() => _statusBarQuickEnabled = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("스크린샷 일지 자동저장", style: TextStyle(color: Colors.white)),
            subtitle: Text("스크린샷 찍을 때 일지 등록", style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _screenshotAutoRegisterEnabled,
            activeThumbColor: Theme.of(context).primaryColor,
            onChanged: (value) async {
              if (value) {
                if (Platform.isAndroid && (await PackageInfo.fromPlatform()).version.startsWith('14')) {
                  final storageStatus = await Permission.manageExternalStorage.request();
                  if (!storageStatus.isGranted) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("파일 접근 권한이 필요합니다.")),
                    );
                    return;
                  }
                } else {
                  final storageStatus = await Permission.storage.request();
                  if (!storageStatus.isGranted) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("파일 접근 권한이 필요합니다.")),
                    );
                    return;
                  }
                }
              }

              await SettingsService.setScreenshotAutoRegisterEnabled(value);
              if (value) {
                await ScreenshotAutoRegisterService.instance.start();
              } else {
                await ScreenshotAutoRegisterService.instance.stop();
              }

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
                    contentPadding: EdgeInsets.zero,
                    title: Text("퀵등록 플로팅버튼", style: TextStyle(color: Colors.white)),
                    subtitle: Text("화면에 빠른 등록 버튼 띄우기", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: overlayEnabled,
                    activeThumbColor: Theme.of(context).primaryColor,
                    onChanged: (value) async {
                      if (value && !SettingsService.isFeatureUnlocked()) {
                        _showAdRewardDialog(context, () async {
                          if (!await _requestSystemAlertWindowPermission()) return;
                          await SettingsService.setOverlayQuickRegisterEnabled(true);
                          await OverlayManager.instance.initOverlay();
                        });
                        return;
                      }

                      if (value) {
                        if (!await _requestSystemAlertWindowPermission()) return;
                      }
                      
                      await SettingsService.setOverlayQuickRegisterEnabled(value);
                      if (value) {
                        await OverlayManager.instance.initOverlay();
                      } else {
                        await OverlayManager.instance.closeOverlay();
                      }
                    },
                  ),
                  if (overlayEnabled)
                    ValueListenableBuilder<double>(
                      valueListenable: SettingsService.overlayButtonSizeNotifier,
                      builder: (context, btnSize, _) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Text("버튼 크기 조절", style: TextStyle(color: Colors.grey, fontSize: 13)),
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
                      }
                    ),
                ],
              );
            }
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text("폰트크기 조절버튼", style: TextStyle(color: Colors.white)),
            value: _showFloatingButtons,
            activeThumbColor: Theme.of(context).primaryColor,
            onChanged: (value) {
              setState(() => _showFloatingButtons = value);
              SettingsService.setShowFloatingButtons(value);
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: SettingsService.addressSearchModeNotifier,
            builder: (context, currentMode, _) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('주소 자동완성 방식', style: TextStyle(color: Colors.white)),
                subtitle: Text('입력 시 추천해 주는 기준 선택', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: DropdownButton<String>(
                  value: currentMode,
                  dropdownColor: Theme.of(context).cardTheme.color,
                  style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14, fontWeight: FontWeight.bold),
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

  Future<bool> _requestSystemAlertWindowPermission() async {
    final status = await Permission.systemAlertWindow.request();
    if (!status.isGranted) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("다른 앱 위에 표시 권한이 필요합니다. 설정에서 허용해 주세요.")),
      );
      return false;
    }
    return true;
  }
""";
    int idx = code.indexOf('  Widget _buildSettingsScrollBody');
    code = code.substring(0, idx) + dialogCode + "\\n" + code.substring(idx);
  }

  // 2. Replace _buildSettingsScrollBody's contents
  final bodyRegex = RegExp(r'Container\(\s*key: _keyFeeInsurance.*?_buildSettingsGroup\(\s*"보험료 설정".*?\),', dotAll: true);
  if (bodyRegex.hasMatch(code)) {
    code = code.replaceAll(bodyRegex, '''      _buildListManageButton(
        title: '수수료 및 보험료 설정',
        icon: Icons.monetization_on_outlined,
        onTap: _showFeeInsuranceDialog,
      ),''');
  }

  // 3. Replace the 3 old settings with _buildAppConvenienceSettings inside _buildSettingsScrollBody
  final oldConvenienceRegex = RegExp(r'if \(!kIsWeb && Platform\.isAndroid\)\s*Container\(\s*key: _keyStatusBarQuick,\s*child: _buildStatusBarQuickSettings\(\),\s*\),\s*_buildFloatingButtonSettings\(\),\s*if \(!kIsWeb && Platform\.isAndroid\)\s*Container\(\s*key: _keyScreenshotAuto,\s*child: _buildScreenshotAutoRegisterSettings\(\),\s*\),', dotAll: true);
  if (oldConvenienceRegex.hasMatch(code)) {
    code = code.replaceAll(oldConvenienceRegex, '''      if (!kIsWeb && Platform.isAndroid)
        Container(
          key: _keyStatusBarQuick,
          child: _buildAppConvenienceSettings(),
        ),''');
  }

  // 4. Remove the old _build methods (StatusBar, Screenshot, FloatingButton)
  final oldMethods = [
    RegExp(r'  Widget _buildStatusBarQuickSettings\(\) \{.*?(?=  Widget _buildFloatingButtonSettings|  Widget _buildProModeTestToggle|  Widget _buildScreenshotAuto)', dotAll: true),
    RegExp(r'  Widget _buildFloatingButtonSettings\(\) \{.*?(?=  Widget _buildScreenshotAuto|  Widget _buildProModeTestToggle|  Widget _buildSettingsScrollBody)', dotAll: true),
    RegExp(r'  Widget _buildScreenshotAutoRegisterSettings\(\) \{.*?(?=  Widget _buildOcrParseLogSettings|  Widget _buildBackupRestore)', dotAll: true)
  ];
  for (var pattern in oldMethods) {
    if (pattern.hasMatch(code)) {
      code = code.replaceAll(pattern, '');
    }
  }

  file.writeAsStringSync(code);
  print("done");
}

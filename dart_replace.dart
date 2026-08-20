import 'dart:io';

void main() {
  final file = File('lib/screens/settings_page.dart');
  String rawCode = file.readAsStringSync();
  String code = rawCode.replaceAll('\r\n', '\n');
  
  // Replace the fee/insurance settings with a dialog trigger
  final feeStartIdx = code.indexOf('      Container(\n        key: _keyFeeInsurance,');
  if (feeStartIdx != -1) {
    final feeEndStr = '.showSnackBar(const SnackBar(content: Text("보험료 설정이 저장되었습니다.")));\n        },\n      ),';
    final feeEndIdx = code.indexOf(feeEndStr, feeStartIdx);
    
    if (feeEndIdx != -1) {
      final realEnd = feeEndIdx + feeEndStr.length;
      final replacement = '''      Container(
        key: _keyFeeInsurance,
        child: _buildListManageButton(
          title: '수수료 및 보험료 설정',
          icon: Icons.monetization_on_outlined,
          onTap: _showFeeInsuranceDialog,
        ),
      ),''';
      code = code.substring(0, feeStartIdx) + replacement + code.substring(realEnd);
    }
  }
  
  // Replace convenience settings
  final convStartIdx = code.indexOf('      if (!kIsWeb && Platform.isAndroid)\n        Container(\n          key: _keyStatusBarQuick,\n          child: _buildStatusBarQuickSettings(),\n        ),');
  if (convStartIdx != -1) {
    final convEndStr = '      if (!kIsWeb && Platform.isAndroid)\n        Container(\n          key: _keyScreenshotAuto,\n          child: _buildScreenshotAutoRegisterSettings(),\n        ),';
    final convEndIdx = code.indexOf(convEndStr, convStartIdx);
    if (convEndIdx != -1) {
      final realEnd = convEndIdx + convEndStr.length;
      final replacement = '''      Container(
        key: _keyStatusBarQuick,
        child: _buildAppConvenienceSettings(),
      ),''';
      code = code.substring(0, convStartIdx) + replacement + code.substring(realEnd);
    }
  }

  // Remove _buildStatusBarQuickSettings block completely
  final statusBarStart = code.indexOf('  Widget _buildStatusBarQuickSettings() {');
  if (statusBarStart != -1) {
    final statusBarEndBlock = '  Widget _buildFloatingButtonSettings() {';
    final statusBarEndIdx = code.indexOf(statusBarEndBlock, statusBarStart);
    if (statusBarEndIdx != -1) {
      code = code.substring(0, statusBarStart) + code.substring(statusBarEndIdx);
    }
  }

  // Remove _buildFloatingButtonSettings block completely
  final fbStart = code.indexOf('  Widget _buildFloatingButtonSettings() {');
  if (fbStart != -1) {
    final fbEndBlock = '  Future<void> _runBatchGeocodeUpdate() async {';
    final fbEndIdx = code.indexOf(fbEndBlock, fbStart);
    if (fbEndIdx != -1) {
      code = code.substring(0, fbStart) + code.substring(fbEndIdx);
    }
  }

  // Remove _buildScreenshotAutoRegisterSettings block completely
  final ssStart = code.indexOf('  Widget _buildScreenshotAutoRegisterSettings() {');
  if (ssStart != -1) {
    final ssEndBlock = '  Widget _buildOcrParseLogSettings() {';
    final ssEndIdx = code.indexOf(ssEndBlock, ssStart);
    if (ssEndIdx != -1) {
      code = code.substring(0, ssStart) + code.substring(ssEndIdx);
    }
  }

  // Insert _showFeeInsuranceDialog & _buildAppConvenienceSettings
  if (!code.contains('void _showFeeInsuranceDialog() {')) {
    final dialogCode = """
  void _showFeeInsuranceDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardTheme.color,
              title: const Text("수수료 및 보험료 설정", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("기본 수수료율 (%)", style: TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseFeeCon,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2C2F3D),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text("보험료 설정", style: TextStyle(color: Colors.white, fontSize: 14)),
                    RadioListTile<String>(
                      title: const Text("적용 안 함", style: TextStyle(color: Colors.white)),
                      value: 'none',
                      groupValue: _insuranceType,
                      activeColor: Theme.of(context).primaryColor,
                      onChanged: (val) {
                        setDialogState(() => _insuranceType = val!);
                        setState(() => _insuranceType = val!);
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text("건당 보험료", style: TextStyle(color: Colors.white)),
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
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "1건당 차감 금액 (원)",
                            labelStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: const Color(0xFF2C2F3D),
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
                  child: const Text("취소", style: TextStyle(color: Colors.grey)),
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
            title: const Text("고정 알림 상태바", style: TextStyle(color: Colors.white)),
            subtitle: const Text("알림 패널에 오늘 순익 표시", style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _statusBarQuickEnabled,
            activeColor: Theme.of(context).primaryColor,
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
                await TodayStatsNotificationService.instance.cancel();
              }

              if (!mounted) return;
              setState(() => _statusBarQuickEnabled = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("스크린샷 일지 자동저장", style: TextStyle(color: Colors.white)),
            subtitle: const Text("스크린샷 찍을 때 일지 등록", style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _screenshotAutoRegisterEnabled,
            activeColor: Theme.of(context).primaryColor,
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
              await ScreenshotAutoRegisterService.instance.syncWithSettingsPreference();

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
                    title: const Text("퀵등록 플로팅버튼", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("화면에 빠른 등록 버튼 띄우기", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: overlayEnabled,
                    activeColor: Theme.of(context).primaryColor,
                    onChanged: (value) async {
                      if (value && !SettingsService.isFeatureUnlocked()) {
                        _showAdRewardDialog(context, () async {
                          if (!await _requestSystemAlertWindowPermission()) return;
                          await SettingsService.setOverlayQuickRegisterEnabled(true);
                          await OverlayManager.showOverlay(context);
                        });
                        return;
                      }

                      if (value) {
                        if (!await _requestSystemAlertWindowPermission()) return;
                      }
                      
                      await SettingsService.setOverlayQuickRegisterEnabled(value);
                      if (value) {
                        await OverlayManager.showOverlay(context);
                      } else {
                        await OverlayManager.closeOverlay();
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
                              const Text("버튼 크기 조절", style: TextStyle(color: Colors.grey, fontSize: 13)),
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
            title: const Text("폰트크기 조절버튼", style: TextStyle(color: Colors.white)),
            value: _showFloatingButtons,
            activeColor: Theme.of(context).primaryColor,
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
                title: const Text('주소 자동완성 방식', style: TextStyle(color: Colors.white)),
                subtitle: const Text('입력 시 추천해 주는 기준 선택', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
    if (idx != -1) {
      code = code.substring(0, idx) + dialogCode + "\n" + code.substring(idx);
    }
  }

  // Insert import if missing
  if (!code.contains("import '../services/overlay_manager.dart';")) {
    code = code.replaceFirst(
        "import '../services/settings_service.dart';", 
        "import '../services/settings_service.dart';\nimport '../services/overlay_manager.dart';");
  }

  if (rawCode.contains('\r\n')) {
    code = code.replaceAll('\n', '\r\n');
  }

  file.writeAsStringSync(code);
}

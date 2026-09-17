import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/feature_usage_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../services/settings_service.dart';
import '../app_glass_dialog.dart';

class AiPremiumSection extends StatefulWidget {
  const AiPremiumSection({Key? key}) : super(key: key);

  @override
  State<AiPremiumSection> createState() => _AiPremiumSectionState();
}

class _AiPremiumSectionState extends State<AiPremiumSection> {
  final TextEditingController _apiKeyCon = TextEditingController();
  final FocusNode _apiKeyFocus = FocusNode();
  bool _isLoadingAd = false;
  bool _isEditingKey = false;

  @override
  void initState() {
    super.initState();
    _apiKeyCon.text = SettingsService.geminiApiKey;
    _isEditingKey = SettingsService.geminiApiKey.isEmpty;
  }

  @override
  void dispose() {
    _apiKeyCon.dispose();
    _apiKeyFocus.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyCon.text.trim();
    await SettingsService.setGeminiApiKey(key);
    if (mounted) {
      setState(() {
        _isEditingKey = key.isEmpty;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ API Key가 저장되었습니다!')),
      );
    }
  }

  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _apiKeyCon.text = data.text!;
      });
    }
  }

  Future<void> _promptEditKey() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: 'API Key 수정',
        content: '기존에 등록된 API Key를 수정하시겠습니까?',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('수정', style: TextStyle(color: Theme.of(context).primaryColor)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _apiKeyCon.clear();
        _isEditingKey = true;
      });
      _apiKeyFocus.requestFocus();
    }
  }

  Future<void> _watchAdForPremium() async {
    setState(() => _isLoadingAd = true);
    try {
      RewardedAdService.showAd(
        onEarnedReward: () async {
          await FeatureUsageService.grantGlobalPremium24h();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 24시간 동안 AI 정밀분석이 활성화됩니다!')),
            );
          }
        },
        onAdClosed: () {
          if (mounted) setState(() => _isLoadingAd = false);
        },
        onAdFailed: () {
          if (mounted) {
            setState(() => _isLoadingAd = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('광고를 불러올 수 없습니다. 잠시 후 다시 시도해주세요.')),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _isLoadingAd = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FeatureUsageService.globalPremiumNotifier,
      builder: (context, isPremium, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Text('AI 정밀분석', style: TextStyle(color: Colors.white)),
                ],
              ),
              subtitle: SettingsService.isRevenueCatPremium && SettingsService.geminiApiKey.isNotEmpty
                  ? const Text(
                      '👑 유료 구독 혜택으로 AI 정밀분석이 자동 활성화되었습니다.',
                      style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                    )
                  : const Text(
                      '오류가 잦은 복잡한 요금이나 주소를 AI가 완벽하게 파싱합니다.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
              activeColor: Theme.of(context).primaryColor,
              value: isPremium,
              onChanged: _isLoadingAd
                  ? null
                  : (val) {
                      if (SettingsService.isRevenueCatPremium && SettingsService.geminiApiKey.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('유료 구독 혜택으로 AI 정밀분석이 항상 활성화되어 있습니다.')),
                        );
                        return;
                      }

                      if (val) {
                        if (SettingsService.geminiApiKey.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gemini API Key를 먼저 입력해야 기능을 사용할 수 있습니다.')),
                          );
                          return;
                        }
                        _watchAdForPremium();
                      } else {
                        FeatureUsageService.clearGlobalPremium();
                      }
                    },
            ),
            
            // API Key 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isEditingKey
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: TextField(
                              controller: _apiKeyCon,
                              focusNode: _apiKeyFocus,
                              style: const TextStyle(fontSize: 14, color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: '등록된 Key가 없습니다',
                                hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.paste, size: 20, color: Colors.white70),
                            onPressed: _pasteApiKey,
                            tooltip: '붙여넣기',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 40),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            onPressed: _saveApiKey,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: const Text('저장', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
                    )
                  : InkWell(
                      onTap: _promptEditKey,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            const Text('등록됨', style: TextStyle(color: Colors.white, fontSize: 14)),
                            const Spacer(),
                            const Text('수정하려면 클릭', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
            ),

            // 가이드 링크 영역
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/app/apikey')),
                    icon: const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
                    label: const Text('무료 발급받기', style: TextStyle(fontSize: 12, color: Colors.blue)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://blog.naver.com/dbros/guide')), // 영상 연동 대기용 링크
                    icon: const Icon(Icons.help_outline, size: 14, color: Colors.grey),
                    label: const Text('발급 가이드', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF2C2F38)),
          ],
        );
      }
    );
  }
}

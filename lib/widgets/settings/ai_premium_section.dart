import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/feature_usage_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../services/settings_service.dart';

class AiPremiumSection extends StatefulWidget {
  const AiPremiumSection({Key? key}) : super(key: key);

  @override
  State<AiPremiumSection> createState() => _AiPremiumSectionState();
}

class _AiPremiumSectionState extends State<AiPremiumSection> {
  final TextEditingController _apiKeyCon = TextEditingController();
  bool _isLoadingAd = false;

  @override
  void initState() {
    super.initState();
    _apiKeyCon.text = SettingsService.geminiApiKey;
  }

  @override
  void dispose() {
    _apiKeyCon.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyCon.text.trim();
    await SettingsService.setGeminiApiKey(key);
    if (mounted) {
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
        return Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타이틀 및 토글 영역
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        const Text('AI 정밀분석 (프리미엄)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                    _isLoadingAd
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : CupertinoSwitch(
                            activeColor: Colors.amber,
                            value: isPremium,
                            onChanged: (val) {
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
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '오류가 잦은 복잡한 요금이나 주소를 AI가 완벽하게 파싱합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              
              // API Key 입력 영역
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextField(
                          controller: _apiKeyCon,
                          style: const TextStyle(fontSize: 14),
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
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.paste, size: 20, color: Colors.black54),
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
                      onPressed: () => launchUrl(Uri.parse('https://blog.naver.com/dbros/guide')), // 임시 링크
                      icon: const Icon(Icons.help_outline, size: 14, color: Colors.grey),
                      label: const Text('발급 가이드', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
            ],
          ),
        );
      }
    );
  }
}

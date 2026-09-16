import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/feature_usage_service.dart';
import '../../services/rewarded_ad_service.dart';
import '../../services/settings_service.dart';
import '../bordered_section.dart';

class AiPremiumSection extends StatefulWidget {
  const AiPremiumSection({Key? key}) : super(key: key);

  @override
  State<AiPremiumSection> createState() => _AiPremiumSectionState();
}

class _AiPremiumSectionState extends State<AiPremiumSection> {
  final TextEditingController _apiKeyCon = TextEditingController();
  bool _isEditingKey = false;
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

  Future<void> _saveKey() async {
    final key = _apiKeyCon.text.trim();
    await SettingsService.setGeminiApiKey(key);
    setState(() {
      _isEditingKey = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API 키가 저장되었습니다.')),
    );
  }

  Future<void> _watchAdForPremium() async {
    setState(() => _isLoadingAd = true);
    try {
      RewardedAdService.showAd(
        onEarnedReward: () async {
          await FeatureUsageService.grantGlobalPremium24h();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ 24시간 프리미엄이 활성화되었습니다!')),
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
    return Container(
      decoration: BorderedSection.decoration(context, borderRadius: 12),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                "AI 정밀분석 기능",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: FeatureUsageService.globalPremiumNotifier,
                builder: (context, isActive, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.purple.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isActive ? Colors.purple : Colors.grey),
                    ),
                    child: Text(
                      isActive ? '프리미엄 활성' : '비활성',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.purpleAccent : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // API Key Input
          const Text('Gemini API Key (무료)', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiKeyCon,
                  obscureText: !_isEditingKey,
                  readOnly: !_isEditingKey,
                  decoration: InputDecoration(
                    hintText: 'AI Studio에서 발급받은 키 입력',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!_isEditingKey)
                ElevatedButton(
                  onPressed: () => setState(() => _isEditingKey = true),
                  child: const Text('수정'),
                )
              else
                ElevatedButton(
                  onPressed: _saveKey,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text('저장', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/app/apikey')),
                  icon: const Icon(Icons.key, size: 16),
                  label: const Text('무료 발급받기', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://youtu.be/dummy')), // Placeholder
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('발급 가이드', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          
          // AdMob Button
          ValueListenableBuilder<bool>(
            valueListenable: FeatureUsageService.globalPremiumNotifier,
            builder: (context, isActive, _) {
              if (isActive) {
                return const Center(
                  child: Text('✅ 24시간 동안 AI 정밀분석을 무제한 사용할 수 있습니다.', 
                    style: TextStyle(fontSize: 13, color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ElevatedButton.icon(
                onPressed: _isLoadingAd ? null : _watchAdForPremium,
                icon: _isLoadingAd 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_circle_outline, color: Colors.white),
                label: const Text('📺 광고 보고 24시간 프리미엄 열기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

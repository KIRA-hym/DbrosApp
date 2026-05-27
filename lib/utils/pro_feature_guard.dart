import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/feature_usage_service.dart';
import '../services/rewarded_ad_service.dart';
import '../config/feature_flags.dart';

class ProFeatureGuard {
  static Future<void> checkAndRun({
    required BuildContext context,
    required String featureKey,
    required Future<bool> Function() canUseFree,
    required Future<bool> Function() canUseWithAd,
    required VoidCallback onGranted,
  }) async {
    if (!kMonetizationEnabled) {
      onGranted();
      return;
    }

    if (SettingsService.isPremiumUser) {
      onGranted();
      return;
    }

    if (await canUseFree()) {
      await FeatureUsageService.incrementFreeUsage(featureKey);
      onGranted();
      return;
    }

    if (await canUseWithAd()) {
      final shouldWatchAd = await _showAdPromptDialog(context, featureKey);
      if (shouldWatchAd == true) {
        // Show loading indicator while ad is loading/showing
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFFFFC700))),
        );

        RewardedAdService.showAd(
          onEarnedReward: () async {
            await FeatureUsageService.incrementAdUsage(featureKey);
            if (context.mounted) Navigator.pop(context); // Close loading
            onGranted();
          },
          onAdClosed: () {
            if (context.mounted) Navigator.pop(context); // Close loading if closed without reward
          },
          onAdFailed: () {
            if (context.mounted) {
              Navigator.pop(context); // Close loading
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('광고 로드에 실패했습니다. 나중에 다시 시도해주세요.')),
              );
            }
          },
        );
      }
      return;
    }

    // No free uses, no ad uses left
    _showProUpgradeDialog(context);
  }

  static Future<bool?> _showAdPromptDialog(BuildContext context, String featureKey) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        title: const Text('무료 이용 횟수 소진', style: TextStyle(color: Colors.white)),
        content: const Text(
          '기본 제공 무료 횟수를 모두 사용했습니다.\n동영상 광고를 시청하시면 추가로 1회 이용하실 수 있습니다.\n광고를 시청하시겠습니까?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC700), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('광고 보고 이용하기'),
          ),
        ],
      ),
    );
  }

  static void _showProUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F222A),
        title: const Text('👑 PRO 전용 기능', style: TextStyle(color: const Color(0xFFFFC700), fontWeight: FontWeight.bold)),
        content: const Text(
          '오늘 이용 가능한 모든 횟수(광고 포함)를 소진했습니다.\nPRO로 업그레이드하고 무제한으로 이용해 보세요!',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC700), foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Navigate to PRO purchase page
            },
            child: const Text('PRO 알아보기'),
          ),
        ],
      ),
    );
  }
}

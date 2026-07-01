import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/feature_usage_service.dart';
import '../services/rewarded_ad_service.dart';
import '../config/feature_flags.dart';
import '../widgets/app_glass_dialog.dart';

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

        bool rewardEarned = false;

        RewardedAdService.showAd(
          onEarnedReward: () async {
            rewardEarned = true;
          },
          onAdClosed: () async {
            if (context.mounted) Navigator.pop(context); // Close loading dialog
            if (rewardEarned) {
              await FeatureUsageService.incrementAdUsage(featureKey);
              onGranted();
            }
          },
          onAdFailed: () {
            if (context.mounted) {
              Navigator.pop(context); // Close loading dialog
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
    return AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.play_circle_outline,
        title: '무료 이용 횟수 소진',
        content: '기본 제공 무료 횟수를 모두 사용했습니다.\n동영상 광고를 시청하시면 추가로 1회 이용하실 수 있습니다.\n광고를 시청하시겠습니까?',
        actions: [
          Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx, false))),
          Builder(
            builder: (ctx) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    );
  }

  static void _showProUpgradeDialog(BuildContext context) {
    AppGlassDialog.show(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.workspace_premium,
        titleWidget: const Text(
          '👑 프리미엄 구독 전용',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: Color(0xFFFFC700),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        content: '오늘 이용 가능한 모든 횟수(광고 포함)를 소진했습니다.\n프리미엄 구독으로 업그레이드하고 무제한으로 이용해 보세요!',
        actions: [
          Builder(builder: (ctx) => GlassDialogCancelButton(onPressed: () => Navigator.pop(ctx), label: '닫기')),
          Builder(
            builder: (ctx) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정식 출시 때 제공될 예정입니다!')),
                );
              },
              child: const Text('프리미엄 구독 알아보기'),
            ),
          ),
        ],
      ),
    );
  }
}

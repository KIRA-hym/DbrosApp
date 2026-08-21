import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/feature_usage_service.dart';
import '../services/rewarded_ad_service.dart';
import '../config/feature_flags.dart';
import '../widgets/app_glass_dialog.dart';
import '../screens/paywall_page.dart';

class ProFeatureGuard {
  static Future<void> checkAndRun({
    required BuildContext context,
    required String featureKey,
    required Future<bool> Function() canUseFree,
    required Future<bool> Function() canUseWithAd,
    required void Function(bool isFreeTicket) onGranted,
    bool autoConsumeFree = true,
  }) async {
    if (!kMonetizationEnabled) {
      onGranted(true);
      return;
    }

    if (SettingsService.isPremiumUser) {
      onGranted(true);
      return;
    }

    // 1. Check if Daily Pass is already active
    if (await FeatureUsageService.hasDailyPassAsync(featureKey)) {
      onGranted(true);
      return;
    }

    // 2. Check Free Uses
    if (await canUseFree()) {
      if (autoConsumeFree) {
        await FeatureUsageService.incrementFreeUsage(featureKey);
      }
      onGranted(true);
      return;
    }

    // 3. Prompt for Ad
    if (await canUseWithAd()) {
      final shouldWatchAd = await _showAdPromptDialog(context, featureKey);
      if (shouldWatchAd == true) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFFC700)),
          ),
        );

        bool rewardEarned = false;

        RewardedAdService.showAd(
          onEarnedReward: () async {
            rewardEarned = true;
          },
          onAdClosed: () async {
            if (context.mounted) Navigator.pop(context); // Close loading dialog
            if (rewardEarned) {
              await FeatureUsageService.incrementAdUsage(
                featureKey,
              ); // This grants the Daily Pass!
              onGranted(false);
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

    // No free uses, no ad uses left (Should rarely happen now since ad uses are infinite)
    _showProUpgradeDialog(context);
  }

  static Future<bool?> _showAdPromptDialog(
    BuildContext context,
    String featureKey,
  ) {
    final bool hasFreeUses =
        (featureKey == 'route_map' || featureKey == 'single_ocr');
    final String title = hasFreeUses ? '무료 이용 횟수 소진' : '기능 일시 잠금 해제';

    String content;
    if (featureKey == 'route_map') {
      content =
          '기본 제공 무료 횟수를 모두 사용했습니다.\n30초 광고를 시청하시면 지도를 1회 열람하실 수 있습니다.\n\n광고를 시청하시겠습니까?';
    } else if (hasFreeUses) {
      content =
          '기본 제공 무료 횟수를 모두 사용했습니다.\n30초 광고를 시청하시면 내일 오전 9시까지 해당 기능을 무제한으로 이용하실 수 있습니다.\n\n광고를 시청하시겠습니까?';
    } else {
      content =
          '30초 광고를 시청하시면 내일 오전 9시까지 해당 기능을 무제한으로 이용하실 수 있습니다.\n\n광고를 시청하시겠습니까?';
    }

    return AppGlassDialog.show<bool>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.play_circle_outline,
        title: title,
        content: content,
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ),
          Builder(
            builder: (ctx) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('시청하기'),
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
          '프리미엄 구독 전용',
          style: TextStyle(
            fontFamily: 'GmarketSans',
            color: Color(0xFFFFC700),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        content: '해당 기능은 프리미엄 구독자 전용입니다.\n구독하시고 무제한으로 이용해 보세요.',
        actions: [
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              onPressed: () => Navigator.pop(ctx),
              label: '닫기',
            ),
          ),
          Builder(
            builder: (ctx) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC700),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PaywallPage()),
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

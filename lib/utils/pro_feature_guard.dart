import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/premium_service.dart';
import '../services/feature_usage_service.dart';
import '../services/rewarded_ad_service.dart';
import '../config/feature_flags.dart';
import '../widgets/app_glass_dialog.dart';
import '../screens/paywall_page.dart';

enum _AdPromptAction {
  startTrial,
  subscribe,
  watchAd,
  cancel,
}

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

    // 1. Check if Timed/Daily Pass is already active (e.g. stats 1h pass)
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

    // 3. Prompt Hybrid Dialog (14-Day Free Trial or Premium Subscribe + Ad Option)
    if (await canUseWithAd()) {
      final action = await _showAdPromptDialog(context, featureKey);
      if (action == _AdPromptAction.startTrial) {
        if (!context.mounted) return;
        final started = await PremiumService.tryStartLaunchTrialWithFeedback(
          context,
        );
        if (started || SettingsService.isPremiumUser) {
          onGranted(true);
        }
        return;
      }

      if (action == _AdPromptAction.subscribe) {
        if (!context.mounted) return;
        final purchased = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => const PaywallPage()),
        );
        if (purchased == true || SettingsService.isPremiumUser) {
          onGranted(true);
        }
        return;
      }

      if (action == _AdPromptAction.watchAd) {
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
              await FeatureUsageService.incrementAdUsage(featureKey);
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

    // Fallback if no ad uses available
    _showProUpgradeDialog(context);
  }

  static Future<_AdPromptAction?> _showAdPromptDialog(
    BuildContext context,
    String featureKey,
  ) {
    final bool canTrial = PremiumService.canStartLaunchTrial;
    final bool hasFreeUses =
        (featureKey == 'route_map' || featureKey == 'single_ocr');
    final bool isStats = (featureKey == 'stats');

    final String title = hasFreeUses
        ? '오늘 무료 이용 횟수를 모두 사용했어요'
        : '프리미엄 편의기능 잠금 해제';

    final String highlightBenefit = isStats ? '1시간 동안만' : '사용 횟수 1회만';
    final String suffixBenefit = isStats
        ? ' 혜택이 적용되고 자동 종료되지만,'
        : ' 충전되지만,';

    final String adButtonLabel = isStats
        ? '📺 30초 광고 보고 1시간만 사용하기'
        : (hasFreeUses ? '📺 30초 광고 보고 1회 충전하기' : '📺 30초 광고 보고 1회 사용하기');

    return AppGlassDialog.show<_AdPromptAction>(
      context: context,
      dialog: AppGlassDialog(
        icon: Icons.workspace_premium,
        title: title,
        contentWidget: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFD1D2D4),
              fontSize: 14,
              height: 1.55,
            ),
            children: [
              const TextSpan(text: '30초 광고를 시청하면 '),
              TextSpan(
                text: highlightBenefit,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(text: '$suffixBenefit\n\n'),
              if (canTrial) ...[
                const TextSpan(text: '아직 사용하지 않은 '),
                const TextSpan(
                  text: '출시기념 14일 무료 체험',
                  style: TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: '을 시작하면 '),
                const TextSpan(
                  text: '결제 없이 14일 동안 광고 없이 모든 기능을 무제한',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: '으로 사용할 수 있습니다.'),
              ] else ...[
                const TextSpan(
                  text: '프리미엄을 구독',
                  style: TextStyle(
                    color: Color(0xFFFFC700),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(
                  text: '하면 매일 광고 없이 모든 기능을 무제한으로 사용할 수 있습니다.',
                ),
              ],
            ],
          ),
        ),
        actions: [
          Builder(
            builder: (ctx) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canTrial
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFFC700),
                foregroundColor: Colors.black,
                elevation: 2,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(
                ctx,
                canTrial
                    ? _AdPromptAction.startTrial
                    : _AdPromptAction.subscribe,
              ),
              child: Text(
                canTrial
                    ? '🎁 출시기념! 결제 없이 14일 무료체험\n즉시 시작하기 (모든 기능 무제한)'
                    : '👑 하루 이용료 100원! 광고 없이\n무제한 사용하기 (프리미엄 구독)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ),
          Builder(
            builder: (ctx) => OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFF282C37),
                foregroundColor: const Color(0xFFE5E7EB),
                side: const BorderSide(color: Colors.white12),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, _AdPromptAction.watchAd),
              child: Text(
                adButtonLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
          Builder(
            builder: (ctx) => GlassDialogCancelButton(
              label: '닫기',
              onPressed: () => Navigator.pop(ctx, _AdPromptAction.cancel),
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

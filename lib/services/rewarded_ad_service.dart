import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class RewardedAdService {
  static RewardedAd? _rewardedAd;
  static bool _isAdLoaded = false;
  // Android 테스트용 ID. 실서비스 시 프로덕션 ID로 교체 필요.
  static const String adUnitId = kReleaseMode 
      ? 'ca-app-pub-3940256099942544/5224354917' 
      : 'ca-app-pub-3940256099942544/5224354917';

  static void loadAd() {
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          _rewardedAd = null;
        },
      ),
    );
  }

  static void showAd({
    required Function onEarnedReward,
    required Function onAdClosed,
    Function? onAdFailed,
  }) {
    if (_rewardedAd == null || !_isAdLoaded) {
      if (onAdFailed != null) {
        onAdFailed();
      } else {
        onAdClosed();
      }
      loadAd();
      return;
    }
    
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _isAdLoaded = false;
        _rewardedAd = null;
        loadAd(); // Preload next ad
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _isAdLoaded = false;
        _rewardedAd = null;
        loadAd(); // Retry loading
        if (onAdFailed != null) {
          onAdFailed();
        } else {
          onAdClosed();
        }
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      onEarnedReward();
    });
  }
}

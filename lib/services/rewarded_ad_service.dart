import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdService {
  static RewardedAd? _rewardedAd;
  static bool _isAdLoaded = false;
  static bool _isLoading = false;
  static Completer<bool>? _loadCompleter;

  static const Duration _onDemandLoadTimeout = Duration(seconds: 8);

  // Android 테스트용 ID. 실서비스 시 프로덕션 ID로 교체 필요.
  static const String adUnitId = kReleaseMode
      ? 'ca-app-pub-8895373923384999/3927806132' // 실제 보상형 광고 ID
      : 'ca-app-pub-3940256099942544/5224354917'; // 테스트용 보상형 광고 ID

  /// 보상형 광고 로드 (중복 호출 방지, 로드 완료 여부 Future 반환)
  static Future<bool> loadAd() {
    if (_isAdLoaded && _rewardedAd != null) {
      return Future<bool>.value(true);
    }
    if (_isLoading && _loadCompleter != null) {
      return _loadCompleter!.future;
    }

    _isLoading = true;
    final completer = Completer<bool>();
    _loadCompleter = completer;

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          _isLoading = false;
          if (!completer.isCompleted) completer.complete(true);
          if (identical(_loadCompleter, completer)) _loadCompleter = null;
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          _rewardedAd = null;
          _isLoading = false;
          if (!completer.isCompleted) completer.complete(false);
          if (identical(_loadCompleter, completer)) _loadCompleter = null;
        },
      ),
    );

    return completer.future;
  }

  /// 보상형 광고 재생. 아직 프리로드가 안 끝났다면 최대 8초 온디맨드 로드 후 바로 재생.
  static Future<void> showAd({
    required Function onEarnedReward,
    required Function onAdClosed,
    Function? onAdFailed,
  }) async {
    if (_rewardedAd == null || !_isAdLoaded) {
      final loaded = await loadAd().timeout(
        _onDemandLoadTimeout,
        onTimeout: () => false,
      );
      if (!loaded || _rewardedAd == null || !_isAdLoaded) {
        if (onAdFailed != null) {
          onAdFailed();
        } else {
          onAdClosed();
        }
        return;
      }
    }

    final adToShow = _rewardedAd!;
    _rewardedAd = null;
    _isAdLoaded = false;

    adToShow.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadAd(); // Preload next ad
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        loadAd(); // Retry loading
        if (onAdFailed != null) {
          onAdFailed();
        } else {
          onAdClosed();
        }
      },
    );

    adToShow.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onEarnedReward();
      },
    );
  }
}

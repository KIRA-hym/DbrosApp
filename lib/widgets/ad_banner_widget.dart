import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/feature_flags.dart';

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  final String _adUnitId = kIsWeb
      ? ''
      : Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111' // Android Test Banner ID
          : 'ca-app-pub-3940256099942544/2934735716'; // iOS Test Banner ID

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (kIsWeb) return; // Web 미지원 임시 방어코드
    
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: AdSize.banner, // 320x50
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kMonetizationEnabled) {
      return const SizedBox.shrink();
    }
    
    if (_bannerAd != null && _isLoaded) {
      return SafeArea(
        child: Container(
          color: const Color(0xFF121418), // 앱 배경색과 통일
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      );
    }
    
    // 광고가 로딩 중이거나 실패한 경우, 레이아웃 밀림 방지를 위해 동일한 높이의 빈 공간 유지
    return SafeArea(
      child: Container(
        color: Colors.transparent,
        width: 320,
        height: 50,
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'settings_service.dart';

class SubscriptionService {
  static const String _googleApiKey = 'goog_dummyKeyForNowSoItDoesNotCrash';
  static const String _appleApiKey = ''; // iOS 誘몄??먯떆 鍮꾩썙??  
  static bool _isInitialized = false;

  /// RevenueCat 珥덇린??  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (kIsWeb) return; // ?뱀뿉?쒕뒗 吏??????
      await Purchases.setLogLevel(LogLevel.debug);

      late PurchasesConfiguration configuration;
      if (Platform.isAndroid) {
        configuration = PurchasesConfiguration(_googleApiKey);
      } else if (Platform.isIOS) {
        if (_appleApiKey.isEmpty) return;
        configuration = PurchasesConfiguration(_appleApiKey);
      } else {
        return;
      }

      await Purchases.configure(configuration);
      _isInitialized = true;

      // 援щℓ ?곹깭(CustomerInfo)媛 蹂寃쎈맆 ?뚮쭏???먮룞 媛먯??섏뿬 ?꾨━誘몄뾼 ?щ? ?낅뜲?댄듃
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _updatePremiumStatus(customerInfo);
      });

      // 珥덇린 ?곹깭 ?뺤씤
      final customerInfo = await Purchases.getCustomerInfo();
      _updatePremiumStatus(customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService init error: $e');
    }
  }

  /// 濡쒓렇???쒖젏??RevenueCat ?쒕쾭???좎? 怨좎쑀 ID ?곌껐
  static Future<void> logIn(String uid) async {
    if (!_isInitialized) return;
    try {
      final logInResult = await Purchases.logIn(uid);
      _updatePremiumStatus(logInResult.customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService logIn error: $e');
    }
  }

  /// 濡쒓렇?꾩썐 ?쒖젏??RevenueCat 濡쒓렇?꾩썐
  static Future<void> logOut() async {
    if (!_isInitialized) return;
    try {
      final customerInfo = await Purchases.logOut();
      _updatePremiumStatus(customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService logOut error: $e');
    }
  }

  /// ?꾩옱 ?먮ℓ 以묒씤 ?곹뭹 紐⑸줉(Offerings) 遺덈윭?ㅺ린
  static Future<Offerings?> getOfferings() async {
    if (!_isInitialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('SubscriptionService getOfferings error: $e');
      return null;
    }
  }

  /// ?곹뭹 寃곗젣
  static Future<bool> purchasePackage(Package package) async {
    if (!_isInitialized) return false;
    try {
      final result = await Purchases.purchasePackage(package);
      _updatePremiumStatus(result.customerInfo);
      
      // 寃곗젣 ?깃났 ???섎굹?쇰룄 ?쒖꽦?붾맂 entitlement媛 ?덈떎硫?true
      return result.customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('SubscriptionService purchase error: $e');
      return false;
    }
  }

  /// 援щℓ ?댁뿭 蹂듭썝
  static Future<bool> restorePurchases() async {
    if (!_isInitialized) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updatePremiumStatus(customerInfo);
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('SubscriptionService restore error: $e');
      return false;
    }
  }

  /// CustomerInfo瑜?湲곕컲?쇰줈 ?????꾨━誘몄뾼 沅뚰븳 ?숆린??  static void _updatePremiumStatus(CustomerInfo customerInfo) {
    // ?대뼡 沅뚰븳?대뱺 ?쒖꽦?붾릺???덈떎硫??꾨━誘몄뾼?쇰줈 媛꾩＜
    final isPremium = customerInfo.entitlements.active.isNotEmpty;
    if (isPremium != SettingsService.isRevenueCatPremium) {
      SettingsService.setRevenueCatPremium(isPremium);
    }
  }
}

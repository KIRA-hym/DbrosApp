import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'settings_service.dart';

class SubscriptionService {
  static const String _googleApiKey = 'test_jeorWqwGMPVDbfRSPuBRHadtguA';
  static const String _appleApiKey = ''; // iOS 미지원시 비워둠
  
  static bool _isInitialized = false;

  /// RevenueCat 초기화
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (kIsWeb) return; // 웹에서는 지원 안 함

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

      // 구매 상태(CustomerInfo)가 변경될 때마다 자동 감지하여 프리미엄 여부 업데이트
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _updatePremiumStatus(customerInfo);
      });

      // 초기 상태 확인
      final customerInfo = await Purchases.getCustomerInfo();
      _updatePremiumStatus(customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService init error: $e');
    }
  }

  /// 로그인 시점에 RevenueCat 서버에 유저 고유 ID 연결
  static Future<void> logIn(String uid) async {
    if (!_isInitialized) return;
    try {
      final logInResult = await Purchases.logIn(uid);
      _updatePremiumStatus(logInResult.customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService logIn error: $e');
    }
  }

  /// 로그아웃 시점에 RevenueCat 로그아웃
  static Future<void> logOut() async {
    if (!_isInitialized) return;
    try {
      final customerInfo = await Purchases.logOut();
      _updatePremiumStatus(customerInfo);
    } catch (e) {
      debugPrint('SubscriptionService logOut error: $e');
    }
  }

  /// 현재 판매 중인 상품 목록(Offerings) 불러오기
  static Future<Offerings?> getOfferings() async {
    if (!_isInitialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('SubscriptionService getOfferings error: $e');
      return null;
    }
  }

  /// 상품 결제
  static Future<bool> purchasePackage(Package package) async {
    if (!_isInitialized) return false;
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      _updatePremiumStatus(customerInfo);
      
      // 결제 성공 시 하나라도 활성화된 entitlement가 있다면 true
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('SubscriptionService purchase error: $e');
      return false;
    }
  }

  /// 구매 내역 복원
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

  /// CustomerInfo를 기반으로 앱 내 프리미엄 권한 동기화
  static void _updatePremiumStatus(CustomerInfo customerInfo) {
    // 어떤 권한이든 활성화되어 있다면 프리미엄으로 간주
    final isPremium = customerInfo.entitlements.active.isNotEmpty;
    if (SettingsService.isPremiumUser != isPremium) {
      SettingsService.setIsPremiumUser(isPremium);
    }
  }
}

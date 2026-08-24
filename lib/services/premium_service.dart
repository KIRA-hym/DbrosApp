import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dbros_app/services/auth_service.dart';
import 'package:dbros_app/services/settings_service.dart';
import 'package:dbros_app/services/subscription_service.dart';

class PremiumService {
  /// 유저의 프리미엄 상태를 반환 (RevenueCat + Firebase 하이브리드)
  static bool get isPremium {
    if (SettingsService.isRevenueCatPremium) return true;

    final userDoc = AuthService.instance.userDoc;
    if (userDoc != null && userDoc.containsKey('premiumUntil')) {
      final premiumUntil = userDoc['premiumUntil'];
      if (premiumUntil is Timestamp) {
        if (premiumUntil.toDate().isAfter(DateTime.now())) {
          return true;
        }
      }
    }
    
    // Fallback for settings cache if offline
    return SettingsService.isPromoPremium;
  }

  /// 14일 무료 체험을 이미 사용했는지 여부
  static bool get hasUsedLaunchTrial {
    final userDoc = AuthService.instance.userDoc;
    if (userDoc != null && userDoc.containsKey('usedPromotionTypes')) {
      final types = List<String>.from(userDoc['usedPromotionTypes'] ?? []);
      return types.contains('launch_trial');
    }
    return false;
  }

  /// 14일 무료 체험 시작
  static Future<void> startLaunchTrial() async {
    final authUser = AuthService.instance.user;
    if (authUser == null) throw Exception("로그인이 필요합니다.");

    final userRef = FirebaseFirestore.instance.collection('users').doc(authUser.uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) return;

      final userData = userSnapshot.data()!;
      final usedPromotionTypes = List<String>.from(userData['usedPromotionTypes'] ?? []);
      
      if (usedPromotionTypes.contains('launch_trial')) {
        throw Exception("이미 무료 체험을 사용하셨습니다.");
      }

      DateTime newPremiumUntil;
      if (userData.containsKey('premiumUntil')) {
        final currentPremiumUntil = (userData['premiumUntil'] as Timestamp?)?.toDate();
        if (currentPremiumUntil != null && currentPremiumUntil.isAfter(DateTime.now())) {
          newPremiumUntil = currentPremiumUntil.add(const Duration(days: 14));
        } else {
          newPremiumUntil = DateTime.now().add(const Duration(days: 14));
        }
      } else {
        newPremiumUntil = DateTime.now().add(const Duration(days: 14));
      }

      transaction.update(userRef, {
        'premiumUntil': Timestamp.fromDate(newPremiumUntil),
        'usedPromotionTypes': FieldValue.arrayUnion(['launch_trial']),
      });
    });

    SettingsService.setPromoPremium(true, durationDays: 14);
  }
}

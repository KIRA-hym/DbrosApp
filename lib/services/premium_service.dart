import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:dbros_app/services/auth_service.dart';
import 'package:dbros_app/services/settings_service.dart';

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

  /// 현재 14일 무료 체험을 새로 시작할 수 있는 대상인지 여부
  static bool get canStartLaunchTrial {
    return !isPremium &&
        !hasUsedLaunchTrial &&
        AuthService.instance.user != null;
  }

  /// 14일 무료 체험 시작
  static Future<void> startLaunchTrial() async {
    final authUser = AuthService.instance.user;
    if (authUser == null) throw Exception("로그인이 필요합니다.");

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(authUser.uid);

    DateTime grantedUntil = DateTime.now().add(const Duration(days: 14));

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) return;

      final userData = userSnapshot.data()!;
      final usedPromotionTypes = List<String>.from(
        userData['usedPromotionTypes'] ?? [],
      );

      if (usedPromotionTypes.contains('launch_trial')) {
        throw Exception("이미 무료 체험을 사용하셨습니다.");
      }

      DateTime newPremiumUntil;
      if (userData.containsKey('premiumUntil')) {
        final currentPremiumUntil =
            (userData['premiumUntil'] as Timestamp?)?.toDate();
        if (currentPremiumUntil != null &&
            currentPremiumUntil.isAfter(DateTime.now())) {
          newPremiumUntil = currentPremiumUntil.add(const Duration(days: 14));
        } else {
          newPremiumUntil = DateTime.now().add(const Duration(days: 14));
        }
      } else {
        newPremiumUntil = DateTime.now().add(const Duration(days: 14));
      }

      grantedUntil = newPremiumUntil;

      transaction.update(userRef, {
        'premiumUntil': Timestamp.fromDate(newPremiumUntil),
        'usedPromotionTypes': FieldValue.arrayUnion(['launch_trial']),
      });
    });

    AuthService.instance.markLaunchTrialUsedLocally(grantedUntil);
    await SettingsService.setPromoPremium(true, expireAt: grantedUntil);
  }

  /// UI에서 원클릭으로 14일 무료 체험을 시작하고 피드백 스낵바를 표시하는 헬퍼
  static Future<bool> tryStartLaunchTrialWithFeedback(
    BuildContext context,
  ) async {
    if (!context.mounted) return false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E676)),
      ),
    );

    try {
      await startLaunchTrial();
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎉 14일 무료 체험이 시작되었습니다! 모든 프리미엄 기능을 광고 없이 무제한으로 이용하세요.',
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '오류 발생: ${e.toString().replaceAll('Exception: ', '')}',
            ),
          ),
        );
      }
      return false;
    }
  }
}

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'settings_service.dart';

enum AuthStatus {
  uninitialized,
  authenticated,
  unauthenticated,
  banned,
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthStatus _status = AuthStatus.uninitialized;
  AuthStatus get status => _status;

  User? _user;
  User? get user => _user;
  
  Map<String, dynamic>? _userDoc;
  Map<String, dynamic>? get userDoc => _userDoc;

  StreamSubscription<DocumentSnapshot>? _userDocSubscription;

  AuthService._internal() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      _status = AuthStatus.unauthenticated;
      _user = null;
      _userDoc = null;
      _cancelSubscription();
      notifyListeners();
    } else {
      // Firebase Auth 확인 즉시 authenticated 상태 전환 → 홈화면 즉시 진입
      // Firestore 동기화 & banned 체크는 백그라운드로 처리
      _user = firebaseUser;
      _status = AuthStatus.authenticated;
      notifyListeners();

      // 백그라운드에서 Firestore 동기화 및 밴 여부 체크
      unawaited(_syncUserToFirestoreBackground(firebaseUser));
    }
  }

  Future<void> _syncUserToFirestoreBackground(User firebaseUser) async {
    try {
      await _syncUserToFirestore(firebaseUser);
    } catch (e) {
      debugPrint('[AuthService] Firestore sync error (non-critical): $e');
    }
    // Firestore 동기화 완료 후 밴 여부 실시간 감지 시작
    _listenToBannedStatus(firebaseUser.uid);
  }

  Future<void> _syncUserToFirestore(User user) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      // 신규 가입
      await docRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'isBanned': false,
        'isAdmin': false,
      });
      _userDoc = {
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'isBanned': false,
        'isAdmin': false,
      };
    } else {
      // 기존 유저 로그인 시간 갱신
      await docRef.update({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'displayName': user.displayName ?? '', // 프로필 업데이트될 수 있으므로
        'photoURL': user.photoURL ?? '',
      });
      _userDoc = snapshot.data();
    }
  }

  void _listenToBannedStatus(String uid) {
    _cancelSubscription();
    _userDocSubscription = _firestore.collection('users').doc(uid).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        _userDoc = snapshot.data();
        final isBanned = _userDoc?['isBanned'] ?? false;
        
        if (isBanned) {
          _status = AuthStatus.banned;
        } else {
          _status = AuthStatus.authenticated;
        }

        // 프리미엄 권한 동기화
        final premiumUntil = _userDoc?['premiumUntil'];
        if (premiumUntil != null && premiumUntil is Timestamp) {
          if (premiumUntil.toDate().isAfter(DateTime.now())) {
            SettingsService.setIsPremiumUser(true);
          } else {
            SettingsService.setIsPremiumUser(false);
          }
        }

        notifyListeners();
      }
    });
  }

  void _cancelSubscription() {
    _userDocSubscription?.cancel();
    _userDocSubscription = null;
  }

  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // 웹 프리뷰 테스트용 가상 로그인 처리
        _status = AuthStatus.authenticated;
        _userDoc = {
          'uid': 'web_dummy_user',
          'email': 'test@example.com',
          'displayName': '웹 테스트 유저',
          'photoURL': '',
          'isBanned': false,
          'isAdmin': false,
        };
        notifyListeners();
        return;
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // 사용자가 취소함

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      // _onAuthStateChanged 에서 후속 처리 진행됨
    } catch (e) {
      debugPrint("구글 로그인 실패: $e");
      rethrow;
    }
  }

  Future<void> signOut() async {
    _cancelSubscription();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // 1. Firestore에서 유저 데이터 삭제
        await _firestore.collection('users').doc(user.uid).delete();
        
        // 2. Firebase Auth에서 계정 삭제
        await user.delete();
        
        // 3. 로그아웃 (상태 초기화)
        await signOut();
      }
    } catch (e) {
      debugPrint("회원 탈퇴 실패: $e");
      rethrow;
    }
  }

  Future<bool> applyPromotionCode(String code) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception("로그인이 필요합니다.");

    final codeRef = _firestore.collection('promotion_codes').doc(code);
    final userRef = _firestore.collection('users').doc(currentUser.uid);

    return await _firestore.runTransaction((transaction) async {
      final codeSnapshot = await transaction.get(codeRef);
      if (!codeSnapshot.exists) {
        throw Exception("존재하지 않는 코드입니다.");
      }

      final data = codeSnapshot.data()!;
      if (data['isUsed'] == true) {
        throw Exception("이미 사용된 코드입니다.");
      }

      final durationMonths = (data['durationMonths'] as num?)?.toInt() ?? 1;

      final userSnapshot = await transaction.get(userRef);
      DateTime newPremiumUntil;
      
      if (userSnapshot.exists && userSnapshot.data()!.containsKey('premiumUntil')) {
        final currentPremiumUntil = (userSnapshot.data()!['premiumUntil'] as Timestamp?)?.toDate();
        if (currentPremiumUntil != null && currentPremiumUntil.isAfter(DateTime.now())) {
          newPremiumUntil = DateTime(currentPremiumUntil.year, currentPremiumUntil.month + durationMonths, currentPremiumUntil.day);
        } else {
          newPremiumUntil = DateTime(DateTime.now().year, DateTime.now().month + durationMonths, DateTime.now().day);
        }
      } else {
        newPremiumUntil = DateTime(DateTime.now().year, DateTime.now().month + durationMonths, DateTime.now().day);
      }

      transaction.update(codeRef, {
        'isUsed': true,
        'usedBy': currentUser.uid,
        'usedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(userRef, {
        'premiumUntil': Timestamp.fromDate(newPremiumUntil),
      });

      return true;
    });
  }
}

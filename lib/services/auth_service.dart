import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
      _user = firebaseUser;
      await _syncUserToFirestore(firebaseUser);
      _listenToBannedStatus(firebaseUser.uid);
    }
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
}

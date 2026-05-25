import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Firestore 통신 전담 — 토큰 저장 · 관리자 푸시 요청.
class PushRepository {
  PushRepository._();
  static final PushRepository instance = PushRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ────────────────────────────────────────
  // FCM 토큰 저장 / 갱신
  // ────────────────────────────────────────

  /// [token]을 Firestore `fcm_tokens` 컬렉션에 upsert 합니다.
  /// 문서 ID = 토큰 앞 50자 (중복 방지). SetOptions(merge) 사용.
  Future<void> saveToken(String token) async {
    try {
      final platform = kIsWeb ? 'web' : Platform.operatingSystem;
      final docId = _tokenDocId(token);
      await _db.collection('fcm_tokens').doc(docId).set({
        'token': token,
        'platform': platform,
        'last_updated': FieldValue.serverTimestamp(),
        'is_active': true,
      }, SetOptions(merge: true));
      debugPrint('[PushRepository] token saved: ${token.substring(0, 16)}…');
    } catch (e) {
      debugPrint('[PushRepository] saveToken error: $e');
    }
  }

  /// 토큰을 비활성화합니다 (앱 삭제 / 토큰 만료 등).
  Future<void> deactivateToken(String token) async {
    try {
      await _db.collection('fcm_tokens').doc(_tokenDocId(token)).update({
        'is_active': false,
        'last_updated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[PushRepository] deactivateToken error: $e');
    }
  }

  // ────────────────────────────────────────
  // 관리자 푸시 요청
  // ────────────────────────────────────────

  /// `admin_push_requests`에 발송 요청 문서를 생성합니다.
  /// Cloud Functions 트리거가 이 문서를 감지해 실제 FCM 발송을 처리합니다.
  Future<void> requestAdminPush(String title, String body) async {
    await _db.collection('admin_push_requests').add({
      'title': title,
      'body': body,
      'created_at': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
    debugPrint('[PushRepository] admin push requested: $title');
  }

  // ────────────────────────────────────────
  // 내부 헬퍼
  // ────────────────────────────────────────

  String _tokenDocId(String token) =>
      token.length > 50 ? token.substring(0, 50) : token;
}

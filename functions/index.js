/**
 * Firebase Cloud Functions — Admin Push Notification
 *
 * 트리거: admin_push_requests/{docId} 문서 생성 (onCreate)
 * 동작:
 *   1. fcm_tokens 에서 is_active == true 인 토큰을 모두 조회
 *   2. sendEachForMulticast 로 FCM 발송
 *   3. 원본 문서 status → 'completed' 업데이트 + 실패 토큰 기록
 *   4. 만료/미등록 토큰은 is_active: false 처리
 *
 * 배포: firebase deploy --only functions
 * 요구 패키지: firebase-admin, firebase-functions (functions/ 내 package.json 에 명시)
 */

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const BATCH_SIZE = 500; // sendEachForMulticast 최대 500건

/**
 * admin_push_requests 문서 생성 시 실행.
 */
exports.sendAdminPush = onDocumentCreated(
  'admin_push_requests/{docId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const docId = event.params.docId;
    const { title, body } = snap.data();

    if (!title || !body) {
      await snap.ref.update({ status: 'error', error: 'title or body missing' });
      return;
    }

    // ── 1. 유효 토큰 목록 조회 ──────────────────────────────────────────
    let tokens = [];
    try {
      const snapshot = await db
        .collection('fcm_tokens')
        .where('is_active', '==', true)
        .get();
      tokens = snapshot.docs.map((d) => d.data().token).filter(Boolean);
    } catch (err) {
      console.error(`[${docId}] fcm_tokens fetch error:`, err);
      await snap.ref.update({ status: 'error', error: String(err) });
      return;
    }

    if (tokens.length === 0) {
      await snap.ref.update({ status: 'completed', sent: 0, failed_tokens: [] });
      console.log(`[${docId}] no active tokens — skipping`);
      return;
    }

    console.log(`[${docId}] sending to ${tokens.length} tokens`);

    // ── 2. 배치 발송 (500건 제한 처리) ───────────────────────────────────
    const failedTokens = [];
    let successCount = 0;

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const chunk = tokens.slice(i, i + BATCH_SIZE);

      const message = {
        notification: { title, body },
        android: {
          priority: 'high',
          notification: {
            channelId: 'fcm_default_channel',
            defaultSound: true,
            defaultVibrateTimings: true,
          }
        },
        tokens: chunk,
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(message);
        successCount += response.successCount;

        // ── 3. 실패 토큰 처리 ────────────────────────────────────────────
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const token = chunk[idx];
            const code = resp.error?.code ?? '';
            console.warn(`[${docId}] failed token [${code}]:`, token.substring(0, 16));

            failedTokens.push({ token: token.substring(0, 20), code });

            // 만료·미등록 토큰은 비활성화
            const invalidCodes = [
              'messaging/registration-token-not-registered',
              'messaging/invalid-registration-token',
              'messaging/invalid-argument',
            ];
            if (invalidCodes.includes(code)) {
              const docRef = db.collection('fcm_tokens').doc(
                token.length > 50 ? token.substring(0, 50) : token,
              );
              docRef.update({ is_active: false, last_updated: admin.firestore.FieldValue.serverTimestamp() })
                .catch((e) => console.error('deactivate token error:', e));
            }
          }
        });
      } catch (err) {
        console.error(`[${docId}] sendEachForMulticast error:`, err);
        failedTokens.push({ chunk_start: i, error: String(err) });
      }
    }

    // ── 4. 원본 문서 status 업데이트 ─────────────────────────────────────
    await snap.ref.update({
      status: 'completed',
      sent: successCount,
      total: tokens.length,
      failed_tokens: failedTokens,
      completed_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`[${docId}] done — sent: ${successCount}/${tokens.length}, failed: ${failedTokens.length}`);
  },
);

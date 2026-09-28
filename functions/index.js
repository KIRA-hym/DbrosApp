const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const BATCH_SIZE = 500;

async function doGenerate() {
  console.log('Start generating call points JSON for App Sync...');

  const [snapshot, corrSnapshot] = await Promise.all([
    db.collection('shared_call_points').orderBy('timestamp', 'desc').limit(20000).get(),
    db.collection('callPointCorrections').get()
  ]);

  const correctionsMap = new Map();
  corrSnapshot.forEach(doc => {
    correctionsMap.set(doc.id, doc.data());
  });

  const points = [];
  const stats = { kakao: 0, logi: 0, colmaner: 0, tmap: 0, handle: 0, total: 0 };

  // 중복 제거: (start_lat 소수점4자리, start_lng 소수점4자리, program) 동일하면
  // timestamp desc 기준 가장 최근 1건만 유지
  const seen = new Set();
  snapshot.forEach(doc => {
    const data = doc.data();
    if (data.start_lat && data.start_lng) {
      const type = data.program || 'other';
      const created_at = data.timestamp ? data.timestamp.toDate().toISOString() : new Date().toISOString();
      const rawKey = `${created_at}_${type}`;
      const corrKey = rawKey.replace(/[^a-zA-Z0-9_\-가-힣]/g, '_');
      
      const corr = correctionsMap.get(corrKey);
      
      let lat = data.start_lat;
      let lng = data.start_lng;
      let sl = data.start_location || '출발지 정보 없음';
      let el = data.end_location || '도착지 정보 없음';

      // 👑 여기서 수정한 좌표/주소를 원본 JSON에 덮어씌움 (앱 연동 시 완벽해짐)
      if (corr) {
        if (corr.lat != null) lat = corr.lat;
        if (corr.lng != null) lng = corr.lng;
        if (corr.sl) sl = corr.sl;
        if (corr.el) el = corr.el;
      }
      
      const latR = parseFloat(lat).toFixed(4);
      const lngR = parseFloat(lng).toFixed(4);
      const dedupKey = `${latR}_${lngR}_${type}`;
      if (seen.has(dedupKey)) return; // 중복 스킵
      seen.add(dedupKey);

      points.push({
        start_lat: lat,
        start_lng: lng,
        type: type,
        start_location: sl,
        end_location: el,
        gross_fare: data.gross_fare || 0,
        drive_time: data.drive_time || '', // 추가된 운행시간
        created_at: created_at
      });

      if (type.includes('카카오')) stats.kakao++;
      else if (type.includes('로지')) stats.logi++;
      else if (type.includes('콜마너')) stats.colmaner++;
      else if (type.includes('티맵')) stats.tmap++;
      else if (type.includes('핸들')) stats.handle++;
      stats.total++;
    }
  });

  const bucket = admin.storage().bucket();

  const dataFile = bucket.file('shared_coordinates.json');
  await dataFile.save(JSON.stringify(points), {
    metadata: { contentType: 'application/json', cacheControl: 'public, max-age=3600' }
  });

  const version = new Date().getTime();
  const metaFile = bucket.file('shared_coordinates_metadata.json');
  await metaFile.save(JSON.stringify({ version: version }), {
    metadata: { contentType: 'application/json', cacheControl: 'public, max-age=60' }
  });

  const adminPayload = {
    updatedAtISO: new Date().toISOString(),
    stats: stats,
    points: points.map(p => ({
      lat: p.start_lat,
      lng: p.start_lng,
      t: p.type,
      sl: p.start_location,
      el: p.end_location,
      f: p.gross_fare,
      dt: p.drive_time, // 추가: 앱에서 인식한 운행시간(문자열)
      time: p.created_at
    }))
  };
  const adminFile = bucket.file('public/call_points_map.json');
  await adminFile.save(JSON.stringify(adminPayload), {
    metadata: { contentType: 'application/json', cacheControl: 'public, max-age=3600' }
  });

  console.log(`Successfully generated JSON files. total=${stats.total} (deduped from ${snapshot.size})`);
  return adminPayload;
}

exports.testGenerate = onRequest({ cors: true }, async (req, res) => {
  try {
    const payload = await doGenerate();
    res.json(payload);
  } catch (err) {
    res.status(500).send(err.toString());
  }
});

exports.sendAdminPush = onDocumentCreated('admin_push_requests/{docId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No data associated with the event");
    return;
  }
  const data = snapshot.data();
  if (data.status !== 'pending') return;

  const title = data.title;
  const body = data.body;

  try {
    const tokensSnapshot = await db.collection('fcm_tokens').get();
    const tokens = [];
    tokensSnapshot.forEach(doc => {
      const tokenData = doc.data();
      if (tokenData.token) {
        tokens.push(tokenData.token);
      }
    });

    if (tokens.length === 0) {
      console.log("No FCM tokens found.");
      await snapshot.ref.update({ status: 'completed', result: 'no_tokens' });
      return;
    }

    const message = {
      notification: { title: title, body: body },
      tokens: tokens
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(response.successCount + " messages were sent successfully");

    await snapshot.ref.update({
      status: 'completed',
      successCount: response.successCount,
      failureCount: response.failureCount
    });
  } catch (error) {
    console.error("Error sending push notification:", error);
    await snapshot.ref.update({
      status: 'error',
      error: error.toString()
    });
  }
});

exports.generateCallPointsJson = onSchedule(
  { schedule: '0 6 * * *', timeZone: 'Asia/Seoul', timeoutSeconds: 300, memory: '512MiB' },
  async (event) => { await doGenerate(); }
);

exports.getCallPointsMap = onRequest({ cors: true }, async (req, res) => {
  try {
    const bucket = admin.storage().bucket();
    const file = bucket.file('public/call_points_map.json');
    const [exists] = await file.exists();
    if (!exists) {
      res.status(404).send('Not Found');
      return;
    }
    const [data] = await file.download();
    res.set('Cache-Control', 'public, max-age=3600');
    res.json(JSON.parse(data.toString('utf8')));
  } catch (err) {
    res.status(500).send(err.toString());
  }
});

exports.revenuecatWebhook = onRequest({ cors: true }, async (req, res) => {
  try {
    const event = req.body.event;
    if (!event) {
      res.status(400).send('No event');
      return;
    }

    const uid = event.app_user_id;
    const type = event.type;

    if (!uid) {
      res.status(400).send('No app_user_id');
      return;
    }

    const activeEvents = ['INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'NON_RENEWING_PURCHASE'];
    const inactiveEvents = ['CANCELLATION', 'EXPIRATION', 'BILLING_ISSUE', 'REFUND'];

    const updateData = {
      rcLastEventType: type,
      rcLastEventTime: admin.firestore.FieldValue.serverTimestamp()
    };

    if (activeEvents.includes(type)) {
      updateData.isRevenueCatPremium = true;
    } else if (inactiveEvents.includes(type)) {
      updateData.isRevenueCatPremium = false;
    }

    await db.collection('users').doc(uid).set(updateData, { merge: true });

    console.log('Updated ' + uid + ' premium status via RevenueCat Webhook (' + type + ')');
    res.status(200).send('OK');
  } catch (err) {
    console.error('RevenueCat Webhook Error:', err);
    res.status(500).send(err.toString());
  }
});

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admob = require('./admob');
exports.fetchAdmobStats = admob.fetchAdmobStats;

const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'dbros-apps-7bbmw4' });

async function run() {
  const db = admin.firestore();
  const snap = await db.collection('callPointCorrections').limit(5).get();
  snap.forEach(doc => {
    console.log("Correction ID in DB:", doc.id);
  });
  
  const rawSnap = await db.collection('shared_call_points').limit(5).get();
  rawSnap.forEach(doc => {
     const data = doc.data();
     const created_at = data.timestamp ? data.timestamp.toDate().toISOString() : new Date().toISOString();
     const type = data.program || 'other';
     const rawKey = created_at + '_' + type;
     const corrKey = rawKey.replace(/[^a-zA-Z0-9_\-°¡-ÆR]/g, '_');
     console.log("Raw doc ID:", doc.id, "=> corrKey would be:", corrKey);
  });
}
run();

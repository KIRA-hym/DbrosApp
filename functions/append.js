const fs = require('fs');
let content = fs.readFileSync('C:\\dbros_app\\functions\\index.js', 'utf8');

// Replace the incorrect generateCallPointsJson implementation
const startIdx = content.indexOf('exports.generateCallPointsJson =');
if (startIdx !== -1) {
    content = content.substring(0, startIdx);
}

const correctFunction = `
const { onSchedule } = require('firebase-functions/v2/scheduler');

exports.generateCallPointsJson = onSchedule(
  {
    schedule: '0 6 * * *',
    timeZone: 'Asia/Seoul',
    timeoutSeconds: 300,
    memory: '512MiB',
  },
  async (event) => {
    try {
      console.log('Start generating call points JSON for App Sync...');
      
      const snapshot = await db.collection('shared_call_points')
        .orderBy('timestamp', 'desc')
        .limit(20000)
        .get();
        
      const points = [];
      const stats = { kakao: 0, logi: 0, colmaner: 0, tmap: 0, total: 0 };

      snapshot.forEach(doc => {
        const data = doc.data();
        if (data.location && data.location.latitude && data.location.longitude) {
          const type = data.platform || 'other';
          points.push({
            start_lat: data.location.latitude,
            start_lng: data.location.longitude,
            type: type,
            created_at: data.timestamp ? data.timestamp.toDate().toISOString() : new Date().toISOString()
          });
          
          if (type.includes('카카오')) stats.kakao++;
          else if (type.includes('로지')) stats.logi++;
          else if (type.includes('콜마너')) stats.colmaner++;
          else if (type.includes('티맵')) stats.tmap++;
          stats.total++;
        }
      });
      
      const bucket = admin.storage().bucket();
      
      // 1. shared_coordinates.json 생성 (App이 기대하는 형태)
      const dataFile = bucket.file('shared_coordinates.json');
      await dataFile.save(JSON.stringify(points), {
        metadata: { contentType: 'application/json', cacheControl: 'public, max-age=3600' }
      });
      
      // 2. shared_coordinates_metadata.json 생성 (App이 기대하는 형태)
      const version = new Date().getTime(); // Unix timestamp as version
      const metaFile = bucket.file('shared_coordinates_metadata.json');
      await metaFile.save(JSON.stringify({ version: version }), {
        metadata: { contentType: 'application/json', cacheControl: 'public, max-age=60' }
      });

      // 3. Admin 웹용 public/call_points_map.json 도 함께 생성 (기존에 짠 React 코드용)
      const adminPayload = {
        updatedAtISO: new Date().toISOString(),
        stats: stats,
        points: points.map(p => ({lat: p.start_lat, lng: p.start_lng, t: p.type}))
      };
      const adminFile = bucket.file('public/call_points_map.json');
      await adminFile.save(JSON.stringify(adminPayload), {
        metadata: { contentType: 'application/json', cacheControl: 'public, max-age=3600' }
      });
      
      console.log('Successfully generated JSON files.');
    } catch (err) {
      console.error('Error generating JSON:', err);
    }
  }
);
`;

fs.writeFileSync('C:\\dbros_app\\functions\\index.js', content + correctFunction);

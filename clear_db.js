const https = require('https');

const projectId = 'dbros-apps-7bbmw4';
const baseUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function request(url, options = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(data ? JSON.parse(data) : null);
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

async function deleteAll(collection) {
  try {
    const data = await request(`${baseUrl}/${collection}`);
    const docs = data && data.documents ? data.documents : [];
    
    if (docs.length === 0) {
      console.log(`[${collection}] No documents found.`);
      return;
    }
    
    console.log(`[${collection}] Found ${docs.length} documents to delete.`);
    for (const doc of docs) {
      console.log(`Deleting ${doc.name}...`);
      await request(`https://firestore.googleapis.com/v1/${doc.name}`, { method: 'DELETE' });
    }
    console.log(`[${collection}] All documents deleted.`);
  } catch (e) {
    console.error(`Error with ${collection}:`, e.message);
  }
}

async function main() {
  await deleteAll('notices');
  await deleteAll('admin_push_requests');
}

main();

const fs = require('fs');
let code = fs.readFileSync('functions/index.js', 'utf8');
const replacement = `exports.sendAdminPush = onDocumentCreated('admin_push_requests/{docId}', async (event) => {
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
});`;
code = code.replace("exports.sendAdminPush = onDocumentCreated('admin_push_requests/{docId}', async (event) => { /* omitted for brevity */ });", replacement);
fs.writeFileSync('functions/index.js', code);
console.log('Fixed sendAdminPush');

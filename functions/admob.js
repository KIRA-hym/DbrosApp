const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

exports.fetchAdmobStats = onSchedule({
  schedule: '0 1 * * *',
  timeZone: 'Asia/Seoul',
  timeoutSeconds: 120, // 넉넉히 지정
}, async (event) => {
  try {
    // 런타임 지연을 막기 위해 함수 실행 시점에 로드
    const { google } = require('googleapis');
    const db = admin.firestore();
    const oauth2Client = new google.auth.OAuth2(
      process.env.GOOGLE_OAUTH_CLIENT_ID,
      process.env.GOOGLE_OAUTH_CLIENT_SECRET,
      'https://developers.google.com/oauthplayground'
    );

    oauth2Client.setCredentials({
      refresh_token: process.env.GOOGLE_OAUTH_REFRESH_TOKEN
    });

    const admob = google.admob({ version: 'v1', auth: oauth2Client });
    
    // 1. 계정 정보(Publisher ID) 가져오기
    const accounts = await admob.accounts.list();
    if (!accounts.data.account || accounts.data.account.length === 0) {
      console.log('No AdMob account found.');
      return;
    }
    const accountName = accounts.data.account[0].name;

    // 2. 어제 날짜 계산
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    
    // YYYY-MM-DD 포맷
    const dateStr = yesterday.toISOString().split('T')[0];
    
    const year = yesterday.getFullYear();
    const month = yesterday.getMonth() + 1;
    const day = yesterday.getDate();

    console.log(`Generating report for ${accountName} on ${dateStr}...`);

    // 3. 어제자 수익 및 노출수 보고서 생성
    const report = await admob.accounts.networkReport.generate({
      parent: accountName,
      requestBody: {
        reportSpec: {
          dateRange: {
            startDate: { year, month, day },
            endDate: { year, month, day }
          },
          metrics: ['ESTIMATED_EARNINGS', 'IMPRESSIONS']
        }
      }
    });

    // 보고서 배열에서 'row' 데이터 추출
    let revenue = 0;
    let impressions = 0;
    
    const rows = report.data.filter(r => r.row);
    if (rows.length > 0) {
      const metrics = rows[0].row.metricValues;
      // Micros(백만분의 1) 단위를 일반 달러로 변환
      if (metrics.ESTIMATED_EARNINGS && metrics.ESTIMATED_EARNINGS.microsValue) {
        revenue = parseInt(metrics.ESTIMATED_EARNINGS.microsValue, 10) / 1000000;
      }
      if (metrics.IMPRESSIONS && metrics.IMPRESSIONS.integerValue) {
        impressions = parseInt(metrics.IMPRESSIONS.integerValue, 10);
      }
    }

    // 4. Firestore에 저장
    await db.collection('admob_stats').doc(dateStr).set({
      date: dateStr,
      revenue: parseFloat(revenue.toFixed(2)),
      impressions: impressions,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log(`AdMob Stats Saved for ${dateStr}: $${revenue.toFixed(2)}, ${impressions} impressions.`);
  } catch (error) {
    console.error('Error fetching AdMob Stats:', error);
  }
});


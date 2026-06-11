/**
 * Dbros App - Google Sheets API Server (Apps Script)
 * 
 * [시트 준비 사항]
 * 1. 새 구글 스프레드시트를 만듭니다.
 * 2. 1번째 줄(Row 1)에 다음 컬럼명을 순서대로 작성합니다. (A~K열)
 *    timestamp | user_id | lat | lng | type | drive_time | program | start_location | waypoint | end_location | gross_fare | memo
 * 3. 확장 프로그램 > Apps Script로 들어와서 이 코드를 붙여넣습니다.
 * 4. 우측 상단 '배포(Deploy)' > '새 배포' > 유형 '웹 앱(Web App)'
 * 5. 실행 권한: '나(Me)' / 액세스 권한: '모든 사용자(Anyone)'로 설정하여 배포합니다.
 * 6. 생성된 '웹 앱 URL'을 복사하여 Dbros 앱 내부에 적용합니다.
 */

const SHEET_NAME = 'Sheet1'; // 시트 이름이 다르다면 수정하세요

// GET 요청 처리 (좌표 다운로드)
function doGet(e) {
  try {
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
    const data = sheet.getDataRange().getValues();
    const headers = data[0];
    const rows = data.slice(1);
    
    // 시트의 데이터를 JSON 배열로 변환
    const result = rows.map(row => {
      let obj = {};
      headers.forEach((header, index) => {
        obj[header] = row[index];
      });
      return obj;
    });
    
    // 텍스트(JSON) 형태로 응답 반환
    return ContentService.createTextOutput(JSON.stringify(result))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({ "error": error.message }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// POST 요청 처리 (내 좌표 업로드)
function doPost(e) {
  try {
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
    const body = JSON.parse(e.postData.contents);
    
    // body가 배열인지 확인 (다중 좌표 전송)
    if (!Array.isArray(body)) {
      throw new Error("Payload must be an array of coordinates");
    }
    
    const newRows = [];
    body.forEach(item => {
      newRows.push([
        item.timestamp || new Date().toISOString(),
        item.user_id || '',
        item.lat || 0.0,
        item.lng || 0.0,
        item.type || 'waypoint',
        item.drive_time || '',
        item.program || '',
        item.start_location || '',
        item.waypoint || '',
        item.end_location || '',
        item.gross_fare || 0,
        item.memo || ''
      ]);
    });
    
    // 데이터가 있으면 시트 맨 아래에 통째로 추가
    if (newRows.length > 0) {
      sheet.getRange(sheet.getLastRow() + 1, 1, newRows.length, newRows[0].length).setValues(newRows);
    }
    
    return ContentService.createTextOutput(JSON.stringify({ "status": "success", "inserted": newRows.length }))
      .setMimeType(ContentService.MimeType.JSON);
      
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({ "status": "error", "message": error.message }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
